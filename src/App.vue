<script setup>
import { computed, onMounted, onUnmounted, reactive, ref } from 'vue'
import { supabase } from './lib/supabase'

const gameDateTime = ref('')
const myTeamName = ref('')
const opponentTeamName = ref('')
const copyFeedback = ref('')
const dbFeedback = ref('')
const validationErrors = ref([])
const authFeedback = ref('')
const authEmail = ref('')
const authPassword = ref('')
const isAuthBusy = ref(false)
const currentUser = ref(null)
const isSaving = ref(false)
const isLoadingGames = ref(false)
const currentGameId = ref(null)
const savedGames = ref([])
const isConfirmModalOpen = ref(false)
const confirmTitle = ref('')
const confirmMessage = ref('')
const confirmActionLabel = ref('')
const confirmActionClass = ref('danger')
const pendingConfirmAction = ref(null)

const createMyTeamStats = () => ({
  score: 0,
  shotsOnTarget: 0,
  shotsMissed: 0,
  fouls: 0,
})

const createOpponentStats = () => ({
  score: 0,
  shotsOnTarget: 0,
  shotsMissed: 0,
  fouls: 0,
})

const createScoreEvent = () => ({
  id: Date.now() + Math.random(),
  timestamp: '',
  team: 'myTeam',
  note: '',
})

const myTeamStats = reactive(createMyTeamStats())
const opponentStats = reactive(createOpponentStats())
const scoreEvents = ref([createScoreEvent()])
let authSubscription = null

const isSupabaseConfigured = computed(() => Boolean(supabase))
const isAuthenticated = computed(() => Boolean(currentUser.value?.id))
const currentUserEmail = computed(() => currentUser.value?.email || '')
const TEAM_NAME_MAX_LENGTH = 80
const TEAM_NAME_PATTERN = /^[A-Za-z0-9]+$/

const parseDateTimeAsEntered = (value) => {
  if (!value) return null

  const match = String(value).match(/^(\d{4})-(\d{2})-(\d{2})[T\s](\d{2}):(\d{2})/)
  if (!match) return null

  const [, year, month, day, hour, minute] = match
  return new Date(
    Number(year),
    Number(month) - 1,
    Number(day),
    Number(hour),
    Number(minute),
    0,
  )
}

const formatDateTime = (value) => {
  if (!value) return 'Not provided'
  const parsed = parseDateTimeAsEntered(value)
  if (!parsed) return 'Not provided'
  return parsed.toLocaleString([], {
    year: 'numeric',
    month: 'numeric',
    day: 'numeric',
    hour: 'numeric',
    minute: '2-digit',
    hour12: true,
  })
}

const formatShortDateTime = (value) => {
  if (!value) return 'No kickoff time'
  const parsed = parseDateTimeAsEntered(value)
  if (!parsed) return 'No kickoff time'
  return parsed.toLocaleString([], {
    year: 'numeric',
    month: 'numeric',
    day: 'numeric',
    hour: 'numeric',
    minute: '2-digit',
    hour12: true,
  })
}

const clampToNonNegative = (value) => Math.max(0, Number(value) || 0)

const normalizeTeamName = (value, fallback) => {
  const trimmed = String(value || '').trim()
  return trimmed || fallback
}

const isValidTeamName = (value) => TEAM_NAME_PATTERN.test(String(value || '').trim())

const normalizeTimestamp = (value) => {
  const cleaned = String(value || '').trim()
  if (!cleaned) return ''
  return /^[0-9]{1,2}:[0-5][0-9]$/.test(cleaned) ? cleaned : ''
}

const rawTimestampIsValid = (value) => {
  const cleaned = String(value || '').trim()
  if (!cleaned) return true
  return /^[0-9]{1,2}:[0-5][0-9]$/.test(cleaned)
}

const sanitizeScoreEventForPayload = (event) => ({
  timestamp: normalizeTimestamp(event.timestamp),
  team: event.team === 'opponent' ? 'away' : 'home',
  note: String(event.note || '').trim().slice(0, 280),
})

const getShotAttempts = (stats) =>
  clampToNonNegative(stats.shotsOnTarget) + clampToNonNegative(stats.shotsMissed)

const getShotAccuracy = (stats) => {
  const attempts = getShotAttempts(stats)
  if (!attempts) return 0
  return (clampToNonNegative(stats.shotsOnTarget) / attempts) * 100
}

const sanitizeMyTeamStats = (stats = {}) => ({
  score: clampToNonNegative(stats.score),
  shotsOnTarget: clampToNonNegative(stats.shotsOnTarget),
  shotsMissed: clampToNonNegative(stats.shotsMissed),
  fouls: clampToNonNegative(stats.fouls),
})

const sanitizeOpponentStats = (stats = {}) => ({
  score: clampToNonNegative(stats.score),
  shotsOnTarget: clampToNonNegative(stats.shotsOnTarget),
  shotsMissed: clampToNonNegative(stats.shotsMissed),
  fouls: clampToNonNegative(stats.fouls),
})

const parseTimestampToSeconds = (timestamp) => {
  if (!timestamp) return Number.MAX_SAFE_INTEGER
  const parts = timestamp.split(':').map((part) => Number(part))

  if (parts.some((part) => Number.isNaN(part))) {
    return Number.MAX_SAFE_INTEGER
  }

  if (parts.length === 2) {
    return parts[0] * 60 + parts[1]
  }

  if (parts.length === 3) {
    return parts[0] * 3600 + parts[1] * 60 + parts[2]
  }

  return Number.MAX_SAFE_INTEGER
}

const bumpStat = (stats, key, delta) => {
  stats[key] = Math.max(0, clampToNonNegative(stats[key]) + delta)
}

const applyVideoTimeMask = (event, inputValue) => {
  const digits = String(inputValue || '')
    .replace(/\D/g, '')
    .slice(0, 4)

  if (!digits) {
    event.timestamp = ''
    return
  }

  if (digits.length <= 2) {
    event.timestamp = digits
    return
  }

  const minutes = digits.slice(0, 2)
  let seconds = digits.slice(2)

  if (seconds.length === 2) {
    seconds = String(Math.min(59, Number(seconds))).padStart(2, '0')
  }

  event.timestamp = `${minutes}:${seconds}`
}

const sortedEvents = computed(() => {
  return scoreEvents.value
    .map((event, index) => ({ ...event, _index: index }))
    .sort((a, b) => {
      const timeDiff = parseTimestampToSeconds(a.timestamp) - parseTimestampToSeconds(b.timestamp)
      if (timeDiff !== 0) return timeDiff
      return a._index - b._index
    })
})

const timelineWithScore = computed(() => {
  let myTeamRunningScore = 0
  let opponentRunningScore = 0

  return sortedEvents.value.map((event) => {
    if (event.team === 'myTeam') {
      myTeamRunningScore += 1
    } else {
      opponentRunningScore += 1
    }

    return {
      ...event,
      myTeamScore: myTeamRunningScore,
      opponentScore: opponentRunningScore,
    }
  })
})

const finalScore = computed(() => {
  const lastEvent = timelineWithScore.value[timelineWithScore.value.length - 1]
  return {
    myTeam: lastEvent ? lastEvent.myTeamScore : 0,
    opponent: lastEvent ? lastEvent.opponentScore : 0,
  }
})

const hasScoreMismatch = computed(() => {
  return (
    clampToNonNegative(myTeamStats.score) !== finalScore.value.myTeam ||
    clampToNonNegative(opponentStats.score) !== finalScore.value.opponent
  )
})

const getEventScoreLabel = (eventId) => {
  const orderedEvent = timelineWithScore.value.find((item) => item.id === eventId)
  if (!orderedEvent) {
    return `${myTeamName.value || 'My team'} 0 - 0 ${opponentTeamName.value || 'Opponent'}`
  }

  return `${myTeamName.value || 'My team'} ${orderedEvent.myTeamScore} - ${orderedEvent.opponentScore} ${opponentTeamName.value || 'Opponent'}`
}

const mapSupabaseError = (error, action) => {
  const message = String(error?.message || '').toLowerCase()
  const details = String(error?.details || '').toLowerCase()
  const combined = `${message} ${details}`

  if (combined.includes('games_home_team_valid') || combined.includes('games_away_team_valid')) {
    return 'Team names are required and must be 1 to 80 characters.'
  }

  if (combined.includes('games_distinct_teams_valid')) {
    return 'My Team and Opponent Team must be different.'
  }

  if (combined.includes('games_score_events_valid')) {
    return 'One or more timeline events are invalid. Use mm:ss timestamps and keep notes under 280 characters.'
  }

  if (combined.includes('games_home_stats_valid') || combined.includes('games_away_stats_valid')) {
    return 'Some team statistics are outside allowed limits.'
  }

  if (combined.includes('games_youtube_summary_length_valid')) {
    return 'Summary text is too long. Reduce notes or timeline detail.'
  }

  if (error?.code === '42501') {
    return 'You do not have permission for this action.'
  }

  if (error?.code === '23514') {
    return 'Submitted data did not pass validation rules. Please review your inputs.'
  }

  if (action === 'load') return 'Could not load saved games right now.'
  if (action === 'save') return 'Could not save this game right now.'
  if (action === 'delete') return 'Could not delete this game right now.'
  return 'Something went wrong while talking to the database.'
}

const mapAuthError = (error, action) => {
  if (!error) return ''
  const message = String(error.message || '').toLowerCase()

  if (message.includes('invalid login credentials')) {
    return 'Invalid email or password.'
  }

  if (message.includes('email not confirmed')) {
    return 'Please confirm your email before signing in.'
  }

  if (message.includes('already registered')) {
    return 'This email is already registered. Try signing in.'
  }

  if (action === 'sign-up') {
    return 'Could not create account right now.'
  }

  return 'Could not sign in right now.'
}

const validateAuthForm = () => {
  const email = String(authEmail.value || '').trim()
  const password = String(authPassword.value || '')

  if (!email || !email.includes('@')) {
    authFeedback.value = 'Enter a valid email address.'
    return false
  }

  if (password.length < 8) {
    authFeedback.value = 'Password must be at least 8 characters.'
    return false
  }

  return true
}

const signIn = async () => {
  if (!supabase) {
    authFeedback.value = 'Supabase is not configured.'
    return
  }

  if (!validateAuthForm()) return

  isAuthBusy.value = true
  const { error } = await supabase.auth.signInWithPassword({
    email: String(authEmail.value).trim(),
    password: String(authPassword.value),
  })
  isAuthBusy.value = false

  if (error) {
    authFeedback.value = mapAuthError(error, 'sign-in')
    return
  }

  authFeedback.value = 'Signed in successfully.'
  authPassword.value = ''
}

const signUp = async () => {
  if (!supabase) {
    authFeedback.value = 'Supabase is not configured.'
    return
  }

  if (!validateAuthForm()) return

  isAuthBusy.value = true
  const { error } = await supabase.auth.signUp({
    email: String(authEmail.value).trim(),
    password: String(authPassword.value),
  })
  isAuthBusy.value = false

  if (error) {
    authFeedback.value = mapAuthError(error, 'sign-up')
    return
  }

  authFeedback.value = 'Account created. Check your email if confirmation is enabled.'
  authPassword.value = ''
}

const signOut = async () => {
  if (!supabase) return

  const { error } = await supabase.auth.signOut()
  if (error) {
    authFeedback.value = 'Could not sign out right now.'
    return
  }

  authFeedback.value = 'Signed out.'
}

const validateBeforeSave = () => {
  const errors = []
  const homeTeam = normalizeTeamName(myTeamName.value, '')
  const awayTeam = normalizeTeamName(opponentTeamName.value, '')

  if (!homeTeam) {
    errors.push('My Team is required.')
  } else {
    if (homeTeam.length > TEAM_NAME_MAX_LENGTH) {
      errors.push('My Team must be 80 characters or fewer.')
    }

    if (!isValidTeamName(homeTeam)) {
      errors.push('My Team can contain letters and numbers only.')
    }
  }

  if (!awayTeam) {
    errors.push('Opponent Team is required.')
  } else {
    if (awayTeam.length > TEAM_NAME_MAX_LENGTH) {
      errors.push('Opponent Team must be 80 characters or fewer.')
    }

    if (!isValidTeamName(awayTeam)) {
      errors.push('Opponent Team can contain letters and numbers only.')
    }
  }

  if (homeTeam && awayTeam && homeTeam.toLowerCase() === awayTeam.toLowerCase()) {
    errors.push('My Team and Opponent Team must be different.')
  }

  if (gameDateTime.value && !parseDateTimeAsEntered(gameDateTime.value)) {
    errors.push('Game Date & Time is invalid.')
  }

  scoreEvents.value.forEach((event, index) => {
    if (!rawTimestampIsValid(event.timestamp)) {
      errors.push(`Timeline row ${index + 1} has an invalid timestamp. Use mm:ss.`)
    }

    if (String(event.note || '').trim().length > 280) {
      errors.push(`Timeline row ${index + 1} note is too long (max 280 characters).`)
    }
  })

  validationErrors.value = errors
  return errors.length === 0
}

const resetForm = () => {
  gameDateTime.value = ''
  myTeamName.value = ''
  opponentTeamName.value = ''
  currentGameId.value = null
  Object.assign(myTeamStats, createMyTeamStats())
  Object.assign(opponentStats, createOpponentStats())
  scoreEvents.value = [createScoreEvent()]
  validationErrors.value = []
  dbFeedback.value = 'Form reset. Ready for a new game.'
}

const openConfirmModal = ({ title, message, actionLabel, actionClass = 'danger', onConfirm }) => {
  confirmTitle.value = title
  confirmMessage.value = message
  confirmActionLabel.value = actionLabel
  confirmActionClass.value = actionClass
  pendingConfirmAction.value = onConfirm
  isConfirmModalOpen.value = true
}

const closeConfirmModal = () => {
  isConfirmModalOpen.value = false
  pendingConfirmAction.value = null
}

const confirmModalAction = async () => {
  if (!pendingConfirmAction.value) {
    closeConfirmModal()
    return
  }

  await pendingConfirmAction.value()
  closeConfirmModal()
}

const requestClearForm = () => {
  openConfirmModal({
    title: 'Clear current form?',
    message: 'This will remove the current unsaved values from the form.',
    actionLabel: 'Clear Form',
    actionClass: 'danger',
    onConfirm: () => resetForm(),
  })
}

const buildMyTeamLine = (name, stats) => {
  const shotAccuracy = getShotAccuracy(stats).toFixed(1)
  return [
    `${name}:`,
    `- Goals: ${clampToNonNegative(stats.score)}`,
    `- Shot Attempts: ${getShotAttempts(stats)}`,
    `- Shots On Target: ${clampToNonNegative(stats.shotsOnTarget)}`,
    `- Shots Missed: ${clampToNonNegative(stats.shotsMissed)}`,
    `- Shooting Accuracy: ${shotAccuracy}%`,
    `- Fouls: ${clampToNonNegative(stats.fouls)}`,
  ]
}

const buildOpponentLine = (name, stats) => {
  const shotAccuracy = getShotAccuracy(stats).toFixed(1)
  return [
    `${name}:`,
    `- Goals: ${clampToNonNegative(stats.score)}`,
    `- Shot Attempts: ${getShotAttempts(stats)}`,
    `- Shots On Target: ${clampToNonNegative(stats.shotsOnTarget)}`,
    `- Shots Missed: ${clampToNonNegative(stats.shotsMissed)}`,
    `- Shooting Accuracy: ${shotAccuracy}%`,
    `- Fouls: ${clampToNonNegative(stats.fouls)}`,
  ]
}

const youtubeSummary = computed(() => {
  const title = `${myTeamName.value || 'My team'} vs ${opponentTeamName.value || 'Opponent'}`
  const timeline = timelineWithScore.value.length
    ? timelineWithScore.value.map((event) => {
        const teamName =
          event.team === 'myTeam'
            ? myTeamName.value || 'My team'
            : opponentTeamName.value || 'Opponent'
        const teamScore = event.team === 'myTeam' ? event.myTeamScore : event.opponentScore
        const timestamp = event.timestamp || '00:00'
        const note = event.note ? ` | ${event.note}` : ''
        return `${timestamp} - ${teamName} (${teamScore})${note}`
      })
    : ['No goals recorded yet.']

  const header = [
    `Match: ${title}`,
    `Kickoff: ${formatDateTime(gameDateTime.value)}`,
    `Final Score: ${myTeamName.value || 'My team'} ${clampToNonNegative(myTeamStats.score)} - ${clampToNonNegative(opponentStats.score)} ${opponentTeamName.value || 'Opponent'}`,
    '',
    'Goal Timeline',
    ...timeline,
    '',
    'Team Stats',
    ...buildMyTeamLine(myTeamName.value || 'My team', myTeamStats),
    '',
    ...buildOpponentLine(opponentTeamName.value || 'Opponent', opponentStats),
  ]

  return header.join('\n')
})

const copySummary = async () => {
  try {
    await navigator.clipboard.writeText(youtubeSummary.value)
    copyFeedback.value = 'Copied to clipboard.'
  } catch {
    copyFeedback.value = 'Could not copy automatically. Select and copy the text manually.'
  }

  setTimeout(() => {
    copyFeedback.value = ''
  }, 2500)
}

const buildPayload = () => ({
  game_datetime: gameDateTime.value || null,
  home_team: normalizeTeamName(myTeamName.value, 'My team'),
  away_team: normalizeTeamName(opponentTeamName.value, 'Opponent'),
  home_stats: {
    score: clampToNonNegative(myTeamStats.score),
    shotsOnTarget: clampToNonNegative(myTeamStats.shotsOnTarget),
    shotsMissed: clampToNonNegative(myTeamStats.shotsMissed),
    fouls: clampToNonNegative(myTeamStats.fouls),
  },
  away_stats: {
    score: clampToNonNegative(opponentStats.score),
    shotsOnTarget: clampToNonNegative(opponentStats.shotsOnTarget),
    shotsMissed: clampToNonNegative(opponentStats.shotsMissed),
    fouls: clampToNonNegative(opponentStats.fouls),
  },
  score_events: scoreEvents.value.map(sanitizeScoreEventForPayload),
  youtube_summary: youtubeSummary.value,
})

const addScoreEvent = () => {
  scoreEvents.value.push(createScoreEvent())
}

const removeScoreEvent = (id) => {
  scoreEvents.value = scoreEvents.value.filter((event) => event.id !== id)
}

const loadSavedGames = async () => {
  if (!supabase) {
    dbFeedback.value = 'Set VITE_SUPABASE_URL and VITE_SUPABASE_ANON_KEY to enable cloud save.'
    return
  }

  if (!isAuthenticated.value) {
    savedGames.value = []
    dbFeedback.value = 'Sign in to load your saved games.'
    return
  }

  isLoadingGames.value = true
  const { data, error } = await supabase
    .from('games')
    .select('id, created_at, game_datetime, home_team, away_team, home_stats, away_stats, score_events')
    .order('created_at', { ascending: false })

  isLoadingGames.value = false

  if (error) {
    dbFeedback.value = mapSupabaseError(error, 'load')
    return
  }

  const games = data || []
  savedGames.value = games.sort((a, b) => {
    const aHasDateTime = Boolean(a.game_datetime)
    const bHasDateTime = Boolean(b.game_datetime)

    if (!aHasDateTime && !bHasDateTime) return 0
    if (!aHasDateTime) return -1
    if (!bHasDateTime) return 1

    return new Date(b.game_datetime).getTime() - new Date(a.game_datetime).getTime()
  })
}

const applySavedGame = (game) => {
  currentGameId.value = game.id
  gameDateTime.value = game.game_datetime ? game.game_datetime.slice(0, 16) : ''
  myTeamName.value = game.home_team || 'My team'
  opponentTeamName.value = game.away_team || 'Opponent'

  Object.assign(myTeamStats, createMyTeamStats(), sanitizeMyTeamStats(game.home_stats || {}))
  Object.assign(opponentStats, createOpponentStats(), sanitizeOpponentStats(game.away_stats || {}))

  const parsedEvents = Array.isArray(game.score_events) ? game.score_events : []
  scoreEvents.value = parsedEvents.length
    ? parsedEvents.map((event, index) => ({
        id: Date.now() + index,
        timestamp: event.timestamp || '',
        team: event.team === 'away' ? 'opponent' : 'myTeam',
        note: event.note || '',
      }))
    : [createScoreEvent()]

  validationErrors.value = []
  dbFeedback.value = 'Loaded saved game. You can edit and click Update Saved Game.'
}

const saveGame = async () => {
  if (!supabase) {
    dbFeedback.value = 'Set the Supabase URL and anon key in your .env file to enable cloud save.'
    return
  }

  if (!isAuthenticated.value) {
    dbFeedback.value = 'Sign in to save games to the cloud.'
    return
  }

  if (!validateBeforeSave()) {
    dbFeedback.value = 'Please fix the validation issues and try again.'
    return
  }

  validationErrors.value = []

  isSaving.value = true
  const wasUpdate = Boolean(currentGameId.value)
  const payload = buildPayload()
  let query = supabase.from('games')

  if (currentGameId.value) {
    query = query.update(payload).eq('id', currentGameId.value).select('id').single()
  } else {
    query = query.insert(payload).select('id').single()
  }

  const { data, error } = await query
  isSaving.value = false

  if (error) {
    dbFeedback.value = mapSupabaseError(error, 'save')
    return
  }

  currentGameId.value = data.id
  dbFeedback.value = wasUpdate ? 'Saved game updated.' : 'Game saved to Supabase.'
  await loadSavedGames()
}

const deleteSavedGame = async (id) => {
  if (!supabase) {
    return
  }

  if (!isAuthenticated.value) {
    dbFeedback.value = 'Sign in to delete saved games.'
    return
  }

  const { error } = await supabase.from('games').delete().eq('id', id)
  if (error) {
    dbFeedback.value = mapSupabaseError(error, 'delete')
    return
  }

  if (currentGameId.value === id) {
    currentGameId.value = null
  }

  dbFeedback.value = 'Saved game deleted.'
  await loadSavedGames()
}

const requestDeleteSavedGame = (id) => {
  openConfirmModal({
    title: 'Delete saved game?',
    message: 'This action permanently removes the selected game from Supabase.',
    actionLabel: 'Delete',
    actionClass: 'danger',
    onConfirm: () => deleteSavedGame(id),
  })
}

onMounted(async () => {
  if (!supabase) return

  const {
    data: { session },
  } = await supabase.auth.getSession()

  currentUser.value = session?.user || null
  if (currentUser.value) {
    loadSavedGames()
  }

  const { data } = supabase.auth.onAuthStateChange((_event, nextSession) => {
    currentUser.value = nextSession?.user || null

    if (currentUser.value) {
      loadSavedGames()
      return
    }

    savedGames.value = []
    currentGameId.value = null
  })

  authSubscription = data.subscription
})

onUnmounted(() => {
  authSubscription?.unsubscribe()
})
</script>

<template>
  <main class="app-shell">
    <section class="hero-panel">
      <p class="eyebrow">Match Analytics</p>
      <h1>Football Match Stat Tracker</h1>
      <p class="subtitle">
        Track simple stats while reviewing YouTube videos. Add score timestamps, and export a
        ready-to-paste match report.
      </p>
    </section>

    <section class="card">
      <h2>Game Details</h2>
      <div class="grid two-col">
        <label>
          Game Date & Time
          <input v-model="gameDateTime" type="datetime-local" />
        </label>
        <div></div>
        <label>
          My Team
          <input v-model="myTeamName" type="text" placeholder="My team" maxlength="80" />
        </label>
        <label>
          Opponent Team
          <input v-model="opponentTeamName" type="text" placeholder="Opponent" maxlength="80" />
        </label>
      </div>
    </section>

    <section class="card">
      <div class="section-head">
        <h2>Cloud Save</h2>
        <button
          type="button"
          class="secondary"
          :disabled="!isSupabaseConfigured || !isAuthenticated"
          @click="loadSavedGames"
        >
          Refresh List
        </button>
      </div>

      <p class="hint" v-if="!isSupabaseConfigured">
        Supabase is not configured yet. Add VITE_SUPABASE_URL and VITE_SUPABASE_ANON_KEY in your .env file.
      </p>

      <div v-else-if="!isAuthenticated" class="auth-box">
        <p class="hint">Sign in to save, edit, and delete your games.</p>
        <div class="grid two-col">
          <label>
            Email
            <input v-model="authEmail" type="email" placeholder="name@email.com" />
          </label>
          <label>
            Password
            <input v-model="authPassword" type="password" placeholder="At least 8 characters" />
          </label>
        </div>
        <div class="actions-row">
          <button type="button" :disabled="isAuthBusy" @click="signIn">
            {{ isAuthBusy ? 'Working...' : 'Sign In' }}
          </button>
          <button type="button" class="secondary" :disabled="isAuthBusy" @click="signUp">
            Create Account
          </button>
        </div>
      </div>

      <div v-else class="actions-row">
        <p class="hint">Signed in as {{ currentUserEmail }}</p>
        <button type="button" class="secondary" @click="signOut">Sign Out</button>
      </div>

      <p class="hint" v-if="authFeedback">{{ authFeedback }}</p>

      <div class="actions-row">
        <button type="button" :disabled="isSaving || !isSupabaseConfigured || !isAuthenticated" @click="saveGame">
          {{ isSaving ? 'Saving...' : currentGameId ? 'Update Saved Game' : 'Save New Game' }}
        </button>
        <button v-if="currentGameId" type="button" class="secondary" @click="resetForm">
          Create New Game
        </button>
        <button type="button" class="danger" @click="requestClearForm">Clear Form</button>
      </div>

      <ul v-if="validationErrors.length" class="error-list">
        <li v-for="(errorText, index) in validationErrors" :key="index">{{ errorText }}</li>
      </ul>

      <p class="hint" v-if="dbFeedback">{{ dbFeedback }}</p>

      <div class="saved-list" v-if="savedGames.length">
        <article class="saved-item" v-for="game in savedGames" :key="game.id">
          <p class="saved-title">{{ game.home_team }} vs {{ game.away_team }}</p>
          <p class="saved-meta">{{ formatShortDateTime(game.game_datetime) }}</p>
          <div class="actions-row">
            <button type="button" class="secondary" @click="applySavedGame(game)">Load for Edit</button>
            <button type="button" class="danger" @click="requestDeleteSavedGame(game.id)">Delete</button>
          </div>
        </article>
      </div>
      <p v-else-if="!isLoadingGames" class="hint">No saved games yet.</p>
      <p v-else class="hint">Loading saved games...</p>
    </section>

    <section class="card">
      <h2>Team Statistics</h2>
      <p class="hint">Use the + and - buttons for quick counting while watching video clips.</p>

      <div class="grid two-col">
        <article class="team-box">
          <h3>{{ myTeamName || 'My team' }}</h3>
          <div class="stat-grid">
            <label>
              Shots On Target
              <div class="counter">
                <button type="button" class="small secondary" @click="bumpStat(myTeamStats, 'shotsOnTarget', -1)">-</button>
                <input :value="myTeamStats.shotsOnTarget" disabled type="number" />
                <button type="button" class="small secondary" @click="bumpStat(myTeamStats, 'shotsOnTarget', 1)">+</button>
              </div>
            </label>
            <label>
              Shots Missed
              <div class="counter">
                <button type="button" class="small secondary" @click="bumpStat(myTeamStats, 'shotsMissed', -1)">-</button>
                <input :value="myTeamStats.shotsMissed" disabled type="number" />
                <button type="button" class="small secondary" @click="bumpStat(myTeamStats, 'shotsMissed', 1)">+</button>
              </div>
            </label>
            <label>
              Fouls
              <div class="counter">
                <button type="button" class="small secondary" @click="bumpStat(myTeamStats, 'fouls', -1)">-</button>
                <input :value="myTeamStats.fouls" disabled type="number" />
                <button type="button" class="small secondary" @click="bumpStat(myTeamStats, 'fouls', 1)">+</button>
              </div>
            </label>
            <label>
              Score
              <div class="counter">
                <button type="button" class="small secondary" @click="bumpStat(myTeamStats, 'score', -1)">-</button>
                <input :value="myTeamStats.score" disabled type="number" />
                <button type="button" class="small secondary" @click="bumpStat(myTeamStats, 'score', 1)">+</button>
              </div>
            </label>
            <p class="stat-text">Shot Attempts: {{ getShotAttempts(myTeamStats) }}</p>
            <p class="stat-text">Shooting Accuracy: {{ getShotAccuracy(myTeamStats).toFixed(1) }}%</p>
          </div>
        </article>

        <article class="team-box">
          <h3>{{ opponentTeamName || 'Opponent' }}</h3>
          <div class="stat-grid">
            <label>
              Shots On Target
              <div class="counter">
                <button type="button" class="small secondary" @click="bumpStat(opponentStats, 'shotsOnTarget', -1)">-</button>
                <input :value="opponentStats.shotsOnTarget" disabled type="number" />
                <button type="button" class="small secondary" @click="bumpStat(opponentStats, 'shotsOnTarget', 1)">+</button>
              </div>
            </label>
            <label>
              Shots Missed
              <div class="counter">
                <button type="button" class="small secondary" @click="bumpStat(opponentStats, 'shotsMissed', -1)">-</button>
                <input :value="opponentStats.shotsMissed" disabled type="number" />
                <button type="button" class="small secondary" @click="bumpStat(opponentStats, 'shotsMissed', 1)">+</button>
              </div>
            </label>
            <label>
              Fouls
              <div class="counter">
                <button type="button" class="small secondary" @click="bumpStat(opponentStats, 'fouls', -1)">-</button>
                <input :value="opponentStats.fouls" disabled type="number" />
                <button type="button" class="small secondary" @click="bumpStat(opponentStats, 'fouls', 1)">+</button>
              </div>
            </label>
            <label>
              Score
              <div class="counter">
                <button type="button" class="small secondary" @click="bumpStat(opponentStats, 'score', -1)">-</button>
                <input :value="opponentStats.score" disabled type="number" />
                <button type="button" class="small secondary" @click="bumpStat(opponentStats, 'score', 1)">+</button>
              </div>
            </label>
            <p class="stat-text">Shot Attempts: {{ getShotAttempts(opponentStats) }}</p>
            <p class="stat-text">Shooting Accuracy: {{ getShotAccuracy(opponentStats).toFixed(1) }}%</p>
          </div>
        </article>
      </div>

      <div class="actions-row">
        <button type="button" :disabled="isSaving || !isSupabaseConfigured || !isAuthenticated" @click="saveGame">
          {{ isSaving ? 'Saving...' : currentGameId ? 'Update Saved Game' : 'Save New Game' }}
        </button>
      </div>
    </section>

    <section class="card">
      <div class="section-head">
        <h2>Score Timeline (YouTube Timestamps)</h2>
      </div>
      <p class="hint" v-if="hasScoreMismatch">
        Score check: Team counters show {{ myTeamName || 'My team' }} {{ myTeamStats.score }} - {{ opponentStats.score }} {{ opponentTeamName || 'Opponent' }},
        but timeline events show {{ myTeamName || 'My team' }} {{ finalScore.myTeam }} - {{ finalScore.opponent }} {{ opponentTeamName || 'Opponent' }}.
      </p>
      <p class="hint" v-else>
        Score check: Team counters match timeline ({{ myTeamName || 'My team' }} {{ finalScore.myTeam }} - {{ finalScore.opponent }} {{ opponentTeamName || 'Opponent' }}).
      </p>

      <div class="timeline-wrap">
        <article v-for="event in scoreEvents" :key="event.id" class="timeline-row">
          <label>
            Video Time (mm:ss)
            <input
              :value="event.timestamp"
              @input="applyVideoTimeMask(event, $event.target.value)"
              inputmode="numeric"
              maxlength="5"
              placeholder="00:00"
              type="text"
            />
          </label>
          <label>
            Team Scored
            <select v-model="event.team">
              <option value="myTeam">{{ myTeamName || 'My team' }}</option>
              <option value="opponent">{{ opponentTeamName || 'Opponent' }}</option>
            </select>
          </label>
          <label>
            Score After Goal (Auto)
            <input :value="getEventScoreLabel(event.id)" disabled type="text" />
          </label>
          <label>
            Note (optional)
            <input v-model="event.note" placeholder="Fast counter attack" type="text" />
          </label>
          <button
            v-if="scoreEvents.length > 1"
            type="button"
            class="danger"
            @click="removeScoreEvent(event.id)"
          >
            Remove
          </button>
        </article>
      </div>

      <div class="actions-row">
        <button type="button" class="secondary" @click="addScoreEvent">Add Timestamp</button>
      </div>

      <div class="actions-row">
        <button type="button" :disabled="isSaving || !isSupabaseConfigured || !isAuthenticated" @click="saveGame">
          {{ isSaving ? 'Saving...' : currentGameId ? 'Update Saved Game' : 'Save New Game' }}
        </button>
      </div>
    </section>

    <section class="card">
      <div class="section-head">
        <h2>YouTube Description Output</h2>
        <button type="button" @click="copySummary">Copy Text</button>
      </div>
      <p class="hint">Paste this directly into your YouTube video description.</p>
      <textarea :value="youtubeSummary" rows="18" readonly></textarea>
      <p class="copy-feedback" v-if="copyFeedback">{{ copyFeedback }}</p>
    </section>

    <div v-if="isConfirmModalOpen" class="modal-backdrop" @click="closeConfirmModal">
      <section class="confirm-modal" role="dialog" aria-modal="true" @click.stop>
        <h3>{{ confirmTitle }}</h3>
        <p class="hint">{{ confirmMessage }}</p>
        <div class="actions-row">
          <button type="button" class="secondary" @click="closeConfirmModal">Cancel</button>
          <button type="button" :class="confirmActionClass" @click="confirmModalAction">
            {{ confirmActionLabel }}
          </button>
        </div>
      </section>
    </div>
  </main>
</template>
