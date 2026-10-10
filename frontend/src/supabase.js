import { createClient } from '@supabase/supabase-js'
import { trackedFetch } from './activity'

// Las claves vienen del archivo .env.local (NO se sube a Git)
const url = import.meta.env.VITE_SUPABASE_URL
const key = import.meta.env.VITE_SUPABASE_KEY

// db.schema = 'erp' → todas las consultas van a nuestro schema, no a public
// global.fetch = trackedFetch → cuenta las consultas en marcha para el aviso "Cargando…" (activity.js)
export const supabase = createClient(url, key, { db: { schema: 'erp' }, global: { fetch: trackedFetch } })
