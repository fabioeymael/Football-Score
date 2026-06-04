<script setup>
import { computed, onMounted, reactive, ref } from 'vue'
import { supabase } from './lib/supabase'

const gameDateTime = ref('')
const homeTeam = ref('Alliance')
const awayTeam = ref('Opponent')
const copyFeedback = ref('')
const dbFeedback = ref('')
const isSaving = ref(false)
const isLoadingGames = ref(false)
const currentGameId = ref(null)
const savedGames = ref([])

const createAllianceStats = () => ({
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
  team: 'home',
  note: '',
})

const homeStats = reactive(createAllianceStats())
const awayStats = reactive(createOpponentStats())
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
  let homeRunningScore = 0
  let awayRunningScore = 0

  return sortedEvents.value.map((event) => {
    if (event.team === 'home') {
      homeRunningScore += 1
    } else {
      awayRunningScore += 1
    }

    return {
      ...event,
      homeScore: homeRunningScore,
      awayScore: awayRunningScore,
    }
  })
})

const finalScore = computed(() => {
  const lastEvent = timelineWithScore.value[timelineWithScore.value.length - 1]
  return {
    home: lastEvent ? lastEvent.homeScore : 0,
    away: lastEvent ? lastEvent.awayScore : 0,
  }
})

const hasScoreMismatch = computed(() => {
  return (
    clampToNonNegative(homeStats.score) !== finalScore.value.home ||
    clampToNonNegative(awayStats.score) !== finalScore.value.away
  )
})

const getEventScoreLabel = (eventId) => {
  const orderedEvent = timelineWithScore.value.find((item) => item.id === eventId)
  if (!orderedEvent) {
    return `${homeTeam.value || 'Alliance'} 0 - 0 ${awayTeam.value || 'Opponent'}`
  }

  return `${homeTeam.value || 'Alliance'} ${orderedEvent.homeScore} - ${orderedEvent.awayScore} ${awayTeam.value || 'Opponent'}`
}

const resetForm = () => {
  gameDateTime.value = ''
  homeTeam.value = 'Alliance'
  awayTeam.value = 'Opponent'
  currentGameId.value = null
  Object.assign(homeStats, createAllianceStats())
  Object.assign(awayStats, createOpponentStats())
  scoreEvents.value = [createScoreEvent()]
  dbFeedback.value = 'Form reset. Ready for a new game.'
}

const buildAllianceLine = (name, stats) => {
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
  const title = `${homeTeam.value || 'Alliance'} vs ${awayTeam.value || 'Opponent'}`
  const header = [
    `Match: ${title}`,
    `Kickoff: ${formatDateTime(gameDateTime.value)}`,
    `Final Score: ${homeTeam.value || 'Alliance'} ${clampToNonNegative(homeStats.score)} - ${clampToNonNegative(awayStats.score)} ${awayTeam.value || 'Opponent'}`,
    '',
    'Team Stats',
    ...buildAllianceLine(homeTeam.value || 'Alliance', homeStats),
    '',
    ...buildOpponentLine(awayTeam.value || 'Opponent', awayStats),
    '',
    'Goal Timeline',
  ]

  const timeline = timelineWithScore.value.length
    ? timelineWithScore.value.map((event) => {
        const teamName = event.team === 'home' ? homeTeam.value || 'Alliance' : awayTeam.value || 'Opponent'
        const timestamp = event.timestamp || '00:00'
        const note = event.note ? ` | ${event.note}` : ''
        return `${timestamp} - ${teamName} (${event.homeScore}-${event.awayScore})${note}`
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
  home_team: homeTeam.value || 'Alliance',
  away_team: awayTeam.value || 'Opponent',
  home_stats: {
    score: clampToNonNegative(homeStats.score),
    shotsOnTarget: clampToNonNegative(homeStats.shotsOnTarget),
    shotsMissed: clampToNonNegative(homeStats.shotsMissed),
    correctPasses: clampToNonNegative(homeStats.correctPasses),
    missedPasses: clampToNonNegative(homeStats.missedPasses),
    fouls: clampToNonNegative(homeStats.fouls),
  },
  away_stats: {
    score: clampToNonNegative(awayStats.score),
    shotsOnTarget: clampToNonNegative(awayStats.shotsOnTarget),
    shotsMissed: clampToNonNegative(awayStats.shotsMissed),
    fouls: clampToNonNegative(awayStats.fouls),
  },
  score_events: scoreEvents.value.map((event) => ({
    timestamp: event.timestamp || '',
    team: event.team === 'away' ? 'away' : 'home',
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
  homeTeam.value = game.home_team || 'Alliance'
  awayTeam.value = game.away_team || 'Opponent'

  Object.assign(homeStats, createAllianceStats(), game.home_stats || {})
  Object.assign(awayStats, createOpponentStats(), game.away_stats || {})

  const parsedEvents = Array.isArray(game.score_events) ? game.score_events : []
  scoreEvents.value = parsedEvents.length
    ? parsedEvents.map((event, index) => ({
        id: Date.now() + index,
        timestamp: event.timestamp || '',
        team: event.team === 'away' ? 'away' : 'home',
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
          Alliance Team
          <input v-model="homeTeam" type="text" placeholder="Alliance" />
        </label>
        <label>
          Opponent Team
          <input v-model="awayTeam" type="text" placeholder="Opponent" />
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
          <h3>{{ homeTeam || 'Alliance' }}</h3>
          <div class="stat-grid">
            <label>
              Score
              <div class="counter">
                <button type="button" class="small secondary" @click="bumpStat(homeStats, 'score', -1)">-</button>
                <input :value="homeStats.score" disabled type="number" />
                <button type="button" class="small secondary" @click="bumpStat(homeStats, 'score', 1)">+</button>
              </div>
            </label>
            <label>
              Shots On Target
              <div class="counter">
                <button type="button" class="small secondary" @click="bumpStat(homeStats, 'shotsOnTarget', -1)">-</button>
                <input :value="homeStats.shotsOnTarget" disabled type="number" />
                <button type="button" class="small secondary" @click="bumpStat(homeStats, 'shotsOnTarget', 1)">+</button>
              </div>
            </label>
            <label>
              Shots Missed
              <div class="counter">
                <button type="button" class="small secondary" @click="bumpStat(homeStats, 'shotsMissed', -1)">-</button>
                <input :value="homeStats.shotsMissed" disabled type="number" />
                <button type="button" class="small secondary" @click="bumpStat(homeStats, 'shotsMissed', 1)">+</button>
              </div>
            </label>
            <label>
              Correct Passes
              <div class="counter">
                <button type="button" class="small secondary" @click="bumpStat(homeStats, 'correctPasses', -1)">-</button>
                <input :value="homeStats.correctPasses" disabled type="number" />
                <button type="button" class="small secondary" @click="bumpStat(homeStats, 'correctPasses', 1)">+</button>
              </div>
            </label>
            <label>
              Missed Passes
              <div class="counter">
                <button type="button" class="small secondary" @click="bumpStat(homeStats, 'missedPasses', -1)">-</button>
                <input :value="homeStats.missedPasses" disabled type="number" />
                <button type="button" class="small secondary" @click="bumpStat(homeStats, 'missedPasses', 1)">+</button>
              </div>
            </label>
            <label>
              Fouls
              <div class="counter">
                <button type="button" class="small secondary" @click="bumpStat(homeStats, 'fouls', -1)">-</button>
                <input :value="homeStats.fouls" disabled type="number" />
                <button type="button" class="small secondary" @click="bumpStat(homeStats, 'fouls', 1)">+</button>
              </div>
            </label>
            <p class="stat-text">Shot Attempts: {{ getShotAttempts(homeStats) }}</p>
            <p class="stat-text">Shooting Accuracy: {{ getShotAccuracy(homeStats).toFixed(1) }}%</p>
            <p class="stat-text">Pass Attempts: {{ getPassAttempts(homeStats) }}</p>
            <p class="stat-text">Pass Accuracy: {{ getPassAccuracy(homeStats).toFixed(1) }}%</p>
          </div>
        </article>

        <article class="team-box">
          <h3>{{ awayTeam || 'Opponent' }}</h3>
          <div class="stat-grid">
            <label>
              Score
              <div class="counter">
                <button type="button" class="small secondary" @click="bumpStat(awayStats, 'score', -1)">-</button>
                <input :value="awayStats.score" disabled type="number" />
                <button type="button" class="small secondary" @click="bumpStat(awayStats, 'score', 1)">+</button>
              </div>
            </label>
            <label>
              Shots On Target
              <div class="counter">
                <button type="button" class="small secondary" @click="bumpStat(awayStats, 'shotsOnTarget', -1)">-</button>
                <input :value="awayStats.shotsOnTarget" disabled type="number" />
                <button type="button" class="small secondary" @click="bumpStat(awayStats, 'shotsOnTarget', 1)">+</button>
              </div>
            </label>
            <label>
              Shots Missed
              <div class="counter">
                <button type="button" class="small secondary" @click="bumpStat(awayStats, 'shotsMissed', -1)">-</button>
                <input :value="awayStats.shotsMissed" disabled type="number" />
                <button type="button" class="small secondary" @click="bumpStat(awayStats, 'shotsMissed', 1)">+</button>
              </div>
            </label>
            <label>
              Fouls
              <div class="counter">
                <button type="button" class="small secondary" @click="bumpStat(awayStats, 'fouls', -1)">-</button>
                <input :value="awayStats.fouls" disabled type="number" />
                <button type="button" class="small secondary" @click="bumpStat(awayStats, 'fouls', 1)">+</button>
              </div>
            </label>
            <p class="stat-text">Shot Attempts: {{ getShotAttempts(awayStats) }}</p>
            <p class="stat-text">Shooting Accuracy: {{ getShotAccuracy(awayStats).toFixed(1) }}%</p>
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
        Score check: Team counters show {{ homeTeam || 'Alliance' }} {{ homeStats.score }} - {{ awayStats.score }} {{ awayTeam || 'Opponent' }},
        but timeline events show {{ homeTeam || 'Alliance' }} {{ finalScore.home }} - {{ finalScore.away }} {{ awayTeam || 'Opponent' }}.
      </p>
      <p class="hint" v-else>
        Score check: Team counters match timeline ({{ homeTeam || 'Alliance' }} {{ finalScore.home }} - {{ finalScore.away }} {{ awayTeam || 'Opponent' }}).
      </p>

      <div class="timeline-wrap">
        <article v-for="event in scoreEvents" :key="event.id" class="timeline-row">
          <label>
            Video Time (mm:ss)
            <input v-model="event.timestamp" placeholder="12:43" type="text" />
          </label>
          <label>
            Team Scored
            <select v-model="event.team">
              <option value="home">{{ homeTeam || 'Alliance' }}</option>
              <option value="away">{{ awayTeam || 'Opponent' }}</option>
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
