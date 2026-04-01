# Saswat Agro (Web + Mobile)

This repository already uses Flutter, so the same codebase runs on:
- Web
- Android
- iOS

## Configure API key (required for chatbot)

Do not hardcode keys in source code. Pass them at build or run time:

```bash
--dart-define=OPENAI_API_KEY=your_key_here
```

Optional ESP URL override:

```bash
--dart-define=ESP_BASE_URL=http://192.168.4.1
```

## Local development

```bash
flutter pub get
flutter run -d chrome --dart-define=OPENAI_API_KEY=your_key_here
```

For Android/iOS, choose connected device/simulator:

```bash
flutter run --dart-define=OPENAI_API_KEY=your_key_here
```

## Production builds

Web:

```bash
flutter build web --release --dart-define=OPENAI_API_KEY=your_key_here
```

Android:

```bash
flutter build apk --release --dart-define=OPENAI_API_KEY=your_key_here
```

iOS:

```bash
flutter build ios --release --no-codesign --dart-define=OPENAI_API_KEY=your_key_here
```

## CI

A GitHub Actions workflow is included at:

`/home/runner/work/saswatagro/saswatagro/.github/workflows/flutter-multi-platform.yml`

Set repository secret `OPENAI_API_KEY` for CI builds.
