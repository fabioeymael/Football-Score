<script setup>
import { computed, onMounted, reactive, ref } from 'vue'
import { supabase } from './lib/supabase'

const gameDateTime = ref('')
const myTeamName = ref('')
const opponentTeamName = ref('')
const copyFeedback = ref('')
const dbFeedback = ref('')
const isSaving = ref(false)
const isLoadingGames = ref(false)
const currentGameId = ref(null)
const savedGames = ref([])

const createMyTeamStats = () => ({
  score: 0,
  shotsOnTarget: 0,
  shotsMissed: 0,
  correctPasses: 0,
  missedPasses: 0,
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

const isSupabaseConfigured = computed(() => Boolean(supabase))

const formatDateTime = (value) => {
  if (!value) return 'Not provided'
  return new Date(value).toLocaleString()
}

const formatShortDateTime = (value) => {
  if (!value) return 'No kickoff time'
  return new Date(value).toLocaleString()
}

const clampToNonNegative = (value) => Math.max(0, Number(value) || 0)

const getShotAttempts = (stats) =>
  clampToNonNegative(stats.shotsOnTarget) + clampToNonNegative(stats.shotsMissed)

const getPassAttempts = (stats) =>
  clampToNonNegative(stats.correctPasses) + clampToNonNegative(stats.missedPasses)

const getShotAccuracy = (stats) => {
  const attempts = getShotAttempts(stats)
  if (!attempts) return 0
  return (clampToNonNegative(stats.shotsOnTarget) / attempts) * 100
}

const getPassAccuracy = (stats) => {
  const attempts = getPassAttempts(stats)
  if (!attempts) return 0
  return (clampToNonNegative(stats.correctPasses) / attempts) * 100
}

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

const resetForm = () => {
  gameDateTime.value = ''
  myTeamName.value = ''
  opponentTeamName.value = ''
  currentGameId.value = null
  Object.assign(myTeamStats, createMyTeamStats())
  Object.assign(opponentStats, createOpponentStats())
  scoreEvents.value = [createScoreEvent()]
  dbFeedback.value = 'Form reset. Ready for a new game.'
}

const buildMyTeamLine = (name, stats) => {
  const shotAccuracy = getShotAccuracy(stats).toFixed(1)
  const passAccuracy = getPassAccuracy(stats).toFixed(1)
  return [
    `${name}:`,
    `- Goals: ${clampToNonNegative(stats.score)}`,
    `- Shot Attempts: ${getShotAttempts(stats)}`,
    `- Shots On Target: ${clampToNonNegative(stats.shotsOnTarget)}`,
    `- Shots Missed: ${clampToNonNegative(stats.shotsMissed)} (${(100 - shotAccuracy).toFixed(1)}%)`,
    `- Shooting Accuracy: ${shotAccuracy}%`,
    `- Correct Passes: ${clampToNonNegative(stats.correctPasses)}`,
    `- Missed Passes: ${clampToNonNegative(stats.missedPasses)}`,
    `- Pass Accuracy: ${passAccuracy}%`,
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
    `- Shots Missed: ${clampToNonNegative(stats.shotsMissed)} (${(100 - shotAccuracy).toFixed(1)}%)`,
    `- Shooting Accuracy: ${shotAccuracy}%`,
    `- Fouls: ${clampToNonNegative(stats.fouls)}`,
  ]
}

const youtubeSummary = computed(() => {
  const title = `${myTeamName.value || 'My team'} vs ${opponentTeamName.value || 'Opponent'}`
  const header = [
    `Match: ${title}`,
    `Kickoff: ${formatDateTime(gameDateTime.value)}`,
    `Final Score: ${myTeamName.value || 'My team'} ${clampToNonNegative(myTeamStats.score)} - ${clampToNonNegative(opponentStats.score)} ${opponentTeamName.value || 'Opponent'}`,
    '',
    'Team Stats',
    ...buildMyTeamLine(myTeamName.value || 'My team', myTeamStats),
    '',
    ...buildOpponentLine(opponentTeamName.value || 'Opponent', opponentStats),
    '',
    'Goal Timeline',
  ]

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

  return [...header, ...timeline].join('\n')
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
  home_team: myTeamName.value || 'My team',
  away_team: opponentTeamName.value || 'Opponent',
  home_stats: {
    score: clampToNonNegative(myTeamStats.score),
    shotsOnTarget: clampToNonNegative(myTeamStats.shotsOnTarget),
    shotsMissed: clampToNonNegative(myTeamStats.shotsMissed),
    correctPasses: clampToNonNegative(myTeamStats.correctPasses),
    missedPasses: clampToNonNegative(myTeamStats.missedPasses),
    fouls: clampToNonNegative(myTeamStats.fouls),
  },
  away_stats: {
    score: clampToNonNegative(opponentStats.score),
    shotsOnTarget: clampToNonNegative(opponentStats.shotsOnTarget),
    shotsMissed: clampToNonNegative(opponentStats.shotsMissed),
    fouls: clampToNonNegative(opponentStats.fouls),
  },
  score_events: scoreEvents.value.map((event) => ({
    timestamp: event.timestamp || '',
    team: event.team === 'opponent' ? 'away' : 'home',
    note: event.note || '',
  })),
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

  isLoadingGames.value = true
  const { data, error } = await supabase
    .from('games')
    .select('id, created_at, game_datetime, home_team, away_team, home_stats, away_stats, score_events')
    .order('created_at', { ascending: false })

  isLoadingGames.value = false

  if (error) {
    dbFeedback.value = `Could not load saved games: ${error.message}`
    return
  }

  savedGames.value = data || []
}

const applySavedGame = (game) => {
  currentGameId.value = game.id
  gameDateTime.value = game.game_datetime ? game.game_datetime.slice(0, 16) : ''
  myTeamName.value = game.home_team || 'My team'
  opponentTeamName.value = game.away_team || 'Opponent'

  Object.assign(myTeamStats, createMyTeamStats(), game.home_stats || {})
  Object.assign(opponentStats, createOpponentStats(), game.away_stats || {})

  const parsedEvents = Array.isArray(game.score_events) ? game.score_events : []
  scoreEvents.value = parsedEvents.length
    ? parsedEvents.map((event, index) => ({
        id: Date.now() + index,
        timestamp: event.timestamp || '',
        team: event.team === 'away' ? 'opponent' : 'myTeam',
        note: event.note || '',
      }))
    : [createScoreEvent()]

  dbFeedback.value = 'Loaded saved game. You can edit and click Update Saved Game.'
}

const saveGame = async () => {
  if (!supabase) {
    dbFeedback.value = 'Set the Supabase URL and anon key in your .env file to enable cloud save.'
    return
  }

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
    dbFeedback.value = `Could not save game: ${error.message}`
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

  const { error } = await supabase.from('games').delete().eq('id', id)
  if (error) {
    dbFeedback.value = `Could not delete game: ${error.message}`
    return
  }

  if (currentGameId.value === id) {
    currentGameId.value = null
  }

  dbFeedback.value = 'Saved game deleted.'
  await loadSavedGames()
}

onMounted(() => {
  loadSavedGames()
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
          <input v-model="myTeamName" type="text" placeholder="My team" />
        </label>
        <label>
          Opponent Team
          <input v-model="opponentTeamName" type="text" placeholder="Opponent" />
        </label>
      </div>
    </section>

    <section class="card">
      <div class="section-head">
        <h2>Cloud Save (Supabase)</h2>
        <button type="button" class="secondary" @click="loadSavedGames">Refresh List</button>
      </div>

      <p class="hint" v-if="!isSupabaseConfigured">
        Supabase is not configured yet. Add VITE_SUPABASE_URL and VITE_SUPABASE_ANON_KEY in your .env file.
      </p>

      <div class="actions-row">
        <button type="button" :disabled="isSaving || !isSupabaseConfigured" @click="saveGame">
          {{ isSaving ? 'Saving...' : currentGameId ? 'Update Saved Game' : 'Save New Game' }}
        </button>
        <button type="button" class="secondary" @click="resetForm">Clear Form</button>
      </div>

      <p class="hint" v-if="dbFeedback">{{ dbFeedback }}</p>

      <div class="saved-list" v-if="savedGames.length">
        <article class="saved-item" v-for="game in savedGames" :key="game.id">
          <p class="saved-title">{{ game.home_team }} vs {{ game.away_team }}</p>
          <p class="saved-meta">{{ formatShortDateTime(game.game_datetime) }}</p>
          <div class="actions-row">
            <button type="button" class="secondary" @click="applySavedGame(game)">Load for Edit</button>
            <button type="button" class="danger" @click="deleteSavedGame(game.id)">Delete</button>
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
              Score
              <div class="counter">
                <button type="button" class="small secondary" @click="bumpStat(myTeamStats, 'score', -1)">-</button>
                <input :value="myTeamStats.score" disabled type="number" />
                <button type="button" class="small secondary" @click="bumpStat(myTeamStats, 'score', 1)">+</button>
              </div>
            </label>
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
              Correct Passes
              <div class="counter">
                <button type="button" class="small secondary" @click="bumpStat(myTeamStats, 'correctPasses', -1)">-</button>
                <input :value="myTeamStats.correctPasses" disabled type="number" />
                <button type="button" class="small secondary" @click="bumpStat(myTeamStats, 'correctPasses', 1)">+</button>
              </div>
            </label>
            <label>
              Missed Passes
              <div class="counter">
                <button type="button" class="small secondary" @click="bumpStat(myTeamStats, 'missedPasses', -1)">-</button>
                <input :value="myTeamStats.missedPasses" disabled type="number" />
                <button type="button" class="small secondary" @click="bumpStat(myTeamStats, 'missedPasses', 1)">+</button>
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
            <p class="stat-text">Shot Attempts: {{ getShotAttempts(myTeamStats) }}</p>
            <p class="stat-text">Shooting Accuracy: {{ getShotAccuracy(myTeamStats).toFixed(1) }}%</p>
            <p class="stat-text">Pass Attempts: {{ getPassAttempts(myTeamStats) }}</p>
            <p class="stat-text">Pass Accuracy: {{ getPassAccuracy(myTeamStats).toFixed(1) }}%</p>
          </div>
        </article>

        <article class="team-box">
          <h3>{{ opponentTeamName || 'Opponent' }}</h3>
          <div class="stat-grid">
            <label>
              Score
              <div class="counter">
                <button type="button" class="small secondary" @click="bumpStat(opponentStats, 'score', -1)">-</button>
                <input :value="opponentStats.score" disabled type="number" />
                <button type="button" class="small secondary" @click="bumpStat(opponentStats, 'score', 1)">+</button>
              </div>
            </label>
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
            <p class="stat-text">Shot Attempts: {{ getShotAttempts(opponentStats) }}</p>
            <p class="stat-text">Shooting Accuracy: {{ getShotAccuracy(opponentStats).toFixed(1) }}%</p>
          </div>
        </article>
      </div>
    </section>

    <section class="card">
      <div class="section-head">
        <h2>Score Timeline (YouTube Timestamps)</h2>
        <button type="button" class="secondary" @click="addScoreEvent">Add Timestamp</button>
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
  </main>
</template>
