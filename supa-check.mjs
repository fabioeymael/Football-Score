import fs from 'fs'
import { createClient } from '@supabase/supabase-js'

const env = Object.fromEntries(
  fs
    .readFileSync('.env', 'utf8')
    .split(/\r?\n/)
    .filter((line) => line && !line.trim().startsWith('#'))
    .map((line) => {
      const idx = line.indexOf('=')
      return [line.slice(0, idx), line.slice(idx + 1)]
    }),
)

const url = env.VITE_SUPABASE_URL
const key = env.VITE_SUPABASE_ANON_KEY

if (!url || !key) {
  console.log('ENV_MISSING')
  process.exit(1)
}

const supabase = createClient(url, key)

const sel = await supabase.from('games').select('id', { count: 'exact' }).limit(1)
if (sel.error) {
  console.log('SELECT_ERROR:' + sel.error.message)
  process.exit(2)
}
console.log('SELECT_OK count=' + (sel.count ?? 0))

const payload = {
  home_team: 'Alliance',
  away_team: 'Opponent',
  home_stats: {
    score: 0,
    shotsOnTarget: 0,
    shotsMissed: 0,
    correctPasses: 0,
    missedPasses: 0,
    fouls: 0,
  },
  away_stats: {
    score: 0,
    shotsOnTarget: 0,
    shotsMissed: 0,
    fouls: 0,
  },
  score_events: [],
  youtube_summary: 'test',
}

const ins = await supabase.from('games').insert(payload).select('id').single()
if (ins.error) {
  console.log('INSERT_ERROR:' + ins.error.message)
  process.exit(3)
}
console.log('INSERT_OK')

const del = await supabase.from('games').delete().eq('id', ins.data.id)
if (del.error) {
  console.log('DELETE_ERROR:' + del.error.message)
  process.exit(4)
}
console.log('DELETE_OK')
