# Alliance Match App

Simple Vue app for football game stats collection while analyzing match videos.

## What it captures

- Game date and kickoff time
- Alliance vs Opponent names
- Alliance score, shots, pass accuracy, fouls
- Opponent score, shots, fouls
- Score timeline with YouTube timestamps (for example `12:43`)
- Copy-ready YouTube summary text

## Supabase cloud save and edit

This app now supports saving, loading, updating, and deleting games with Supabase.

1. Create a Supabase project.
2. Open Supabase SQL editor and run [supabase-schema.sql](supabase-schema.sql).
3. Copy `.env.example` to `.env`.
4. Fill in:

```bash
VITE_SUPABASE_URL=your-project-url
VITE_SUPABASE_ANON_KEY=your-anon-key
```

5. Restart the dev server.

6. In Supabase Authentication settings, enable Email/Password sign-in.

## hCaptcha setup (required if CAPTCHA is enabled)

If CAPTCHA protection is enabled in Supabase Auth, you must configure hCaptcha in both Supabase and this app.

1. In hCaptcha, create a site and copy your Site Key and Secret Key.
2. In Supabase Dashboard, open Authentication settings for CAPTCHA/Bot Detection.
3. Enable hCaptcha and paste the Site Key and Secret Key.
4. Add only the public Site Key to your app env:

```bash
VITE_HCAPTCHA_SITE_KEY=your-hcaptcha-site-key
```

5. Restart and redeploy the app after updating env values.

Notes:

- The value of `VITE_HCAPTCHA_SITE_KEY` must match the Site Key configured in Supabase.
- Never put the hCaptcha Secret Key in `VITE_` environment variables. `VITE_` values are bundled into frontend JavaScript.
- If they do not match, sign-up/sign-in will fail with captcha token errors.

When configured, use the **Cloud Save (Supabase)** section in the app to:

- Sign in or create an account
- Save New Game
- Load for Edit
- Update Saved Game
- Delete

Security notes:

- Cloud actions now require a signed-in user.
- Row Level Security policies allow each user to access only their own games.

## Run locally

```bash
npm install
npm run dev
npm run dev -- --host
```

## Build

```bash
npm run build
```

## Deploy to GitHub Pages

1. Create a GitHub repository and push this project.
2. Run:

```bash
npm run deploy
```

3. In GitHub repository settings:
	- Open **Pages**
	- Set source to **Deploy from a branch**
	- Select branch **gh-pages** and folder **/**

After deployment, GitHub will provide your hosted app URL.
