# Guía de Git del proyecto (plantilla)

Guía para trabajar con Git **sin ser técnico**. Copia los bloques y **sustituye lo que está entre `< >`**
(sin los símbolos `< >`). Todo se ejecuta en el terminal de VS Code.

---

## 0. Conceptos en una línea

| Palabra | Qué es |
|---|---|
| **Repositorio** | La carpeta del proyecto con todo su historial de cambios. |
| **Commit** | Una "foto" guardada de los cambios, con un mensaje que explica qué se hizo. |
| **Rama (branch)** | Una copia de trabajo para hacer un cambio sin tocar la versión buena. |
| **`main`** | La rama principal: la versión que se publica en la web (Cloudflare la despliega sola). |
| **Push** | Subir tus commits a GitHub. |
| **Pull** | Bajar a tu ordenador lo que hay en GitHub. |
| **Pull request (PR)** | Petición en GitHub para unir una rama a `main`, revisando antes los cambios. |
| **Merge** | Unir una rama a otra (normalmente a `main`). |
| **Tag (etiqueta)** | Un nombre fijo para una versión, por ejemplo `v0.13.0`. |

---

## 1. Las dos terminales

| Terminal | Carpeta | Para qué |
|---|---|---|
| `web` | `D:\01_PROYECTOS_ACTIVOS\09_MiniERP\MiniERP\frontend` | Arrancar la web con `npm run dev` |
| `git` | `D:\01_PROYECTOS_ACTIVOS\09_MiniERP\MiniERP` | Todo lo de Git |

```powershell
# Ir a la carpeta de Git (raíz del proyecto)
cd D:\01_PROYECTOS_ACTIVOS\09_MiniERP\MiniERP

# Ir a la carpeta de la web y arrancarla (Ctrl + C para pararla)
cd D:\01_PROYECTOS_ACTIVOS\09_MiniERP\MiniERP\frontend
npm run dev
```

> **Regla de oro:** los comandos `git` siempre desde la **raíz** (`...\MiniERP>`); los `npm`, desde `frontend`.

---

## 2. El ciclo completo de un cambio (plantilla)

Sustituye `<tipo>/<nombre-rama>`, `<mensaje>` y `<vX.Y.Z>`.

### Paso 1 · Empezar: traer `main` al día y crear la rama
```powershell
git switch main                       # ir a la rama principal
git pull                              # bajar lo último de GitHub
git status                            # debe decir "working tree clean"
git switch -c <tipo>/<nombre-rama>    # crear la rama nueva y entrar en ella
```
Ejemplo: `git switch -c feature/tax-settlement`

### Paso 2 · Trabajar
Editar archivos, probar con `npm run dev`, ejecutar migraciones en Supabase…

### Paso 3 · Guardar (commit) y subir (push)
```powershell
git status                            # ver qué archivos han cambiado
git add -A                            # preparar TODOS los cambios del proyecto
git status                            # comprobar que están todos (en verde)
git commit -m "<mensaje>"             # guardar la foto con su explicación
git push -u origin <tipo>/<nombre-rama>   # subir la rama a GitHub
```

### Paso 4 · Pull request en GitHub (en el navegador)
1. Entra en el repositorio en GitHub: aparece el aviso amarillo **"Compare & pull request"** ? púlsalo.
2. **Título**: la versión y qué hace, por ejemplo `v0.13.0 · Demo sin registro`.
3. **Descripción** (opcional): qué cambia y cómo se probó.
4. **Create pull request**.
5. Revisa la pestaña **Files changed** (qué archivos entran).
6. **Merge pull request** ? **Confirm merge**.
7. (Opcional) **Delete branch** para borrar la rama en GitHub.

### Paso 5 · Cerrar: bajar `main`, etiquetar la versión y limpiar
```powershell
git switch main
git pull                                         # bajar el merge
git tag -a <vX.Y.Z> -m "<vX.Y.Z> · <título>"     # poner la etiqueta de versión
git push --tags                                  # subir la etiqueta
git branch -d <tipo>/<nombre-rama>               # borrar la rama en tu ordenador
git status                                       # debe decir "working tree clean"
```

---

## 3. Nombres de ramas

| Prefijo | Cuándo | Ejemplo |
|---|---|---|
| `feature/` | Funcionalidad nueva | `feature/invoices` |
| `fix/` | Corregir un error | `fix/trial-balance-totals` |
| `docs/` | Solo documentación | `docs/guia-git` |
| `chore/` | Mantenimiento (ordenar, sincronizar) | `chore/sync-db-docs` |

Minúsculas, sin espacios ni tildes, palabras separadas con guiones.

---

## 4. Mensajes de commit

Formato: `<tipo>: <qué hace, en presente>`

| Tipo | Uso | Ejemplo |
|---|---|---|
| `feat` | Funcionalidad nueva | `feat: liquidación trimestral de IVA/IGIC` |
| `fix` | Corrección | `fix: totales del balance de sumas y saldos` |
| `docs` | Documentación | `docs: guía de Git del proyecto` |
| `style` / `feat(ui)` | Cambios visuales | `feat(ui): banderas en el selector de idioma` |
| `chore` | Mantenimiento | `chore: añade migraciones que faltaban` |

---

## 5. Versiones (etiquetas)

Formato **vMAYOR.MENOR.PARCHE** (versionado semántico):

| Sube… | Cuándo | Ejemplo |
|---|---|---|
| **PARCHE** `0.13.0 ? 0.13.1` | Arreglos o retoques sin funcionalidad nueva | Corregir un texto, un color |
| **MENOR** `0.13.1 ? 0.14.0` | Funcionalidad nueva | Registro de facturas |
| **MAYOR** `0.x ? 1.0.0` | El proyecto se considera estable para otros | — |

Después de `0.9.0` viene `0.10.0` (cada número es independiente).
Cada versión se anota en `CHANGELOG.md` y en `docs/bitacora.md`.

---

## 6. Comandos útiles para consultar

```powershell
git status                     # qué ha cambiado y en qué rama estoy
git branch                     # ramas en mi ordenador (la actual con *)
git log --oneline -10          # últimos 10 commits
git log --oneline --graph --all -20   # historial con ramas dibujadas
git diff                       # ver los cambios línea a línea (salir con q)
git tag                        # versiones etiquetadas
```

---

## 7. Problemas frecuentes y solución

| Situación | Qué pasa | Solución |
|---|---|---|
| `npm error ... Could not read package.json` | Estás en la raíz, no en `frontend` | `cd frontend` y repetir |
| El PR solo lleva parte de los archivos | Se hizo `git add .` dentro de `frontend` | Desde la raíz: `git add -A`, `git commit`, `git push` |
| `fatal: a branch named 'X' already exists` | La rama ya existe | `git switch X` (sin `-c`) |
| Hice cambios en `main` sin crear rama | Aún no hay commit | `git switch -c <tipo>/<nombre>`: los cambios viajan a la rama nueva |
| Quiero descartar los cambios de un archivo | Volver a la última versión guardada | `git restore <ruta/archivo>` ? se pierden esos cambios |
| `git pull` dice que hay cambios locales | Tienes cambios sin guardar | Haz commit en una rama, o `git stash` ? `git pull` ? `git stash pop` |
| Tras el merge, la web publicada no cambia | Cloudflare tarda 1–2 min | Revisar en Cloudflare ? *Deployments* |

> Los cambios **sin commit no pertenecen a ninguna rama**: viajan contigo al cambiar de rama.
> Por eso, antes de cambiar de rama, `git status` debe estar limpio.

---

## 8. Qué NO subir nunca

- `frontend/.env.local` (claves de Supabase): ya está en `.gitignore`.
- La clave **secret / service_role** de Supabase: no debe estar en ningún archivo del proyecto.
- Contraseñas o datos personales reales.