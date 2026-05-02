# flutterl10

`flutterl10` is a Dart command-line tool for moving static Flutter UI text into
`app_en.arb`.

It scans Dart files inside a Flutter app's `lib` folder with the Dart analyzer,
finds visible UI strings, adds them to the English ARB file, and replaces the
UI expressions with `AppLocalizations.of(context)!` keys.

## Add from GitHub

Add `flutterl10` to your Flutter project's `pubspec.yaml` as a Git dependency:

```yaml
dev_dependencies:
  flutterl10:
    git:
      url: https://github.com/Parasgiri5637/flutterl10.git
```

Then run:

```bash
flutter pub get
```

Run the tool with `dart run` from your Flutter project root:

```bash
dart run flutterl10 scan
dart run flutterl10 apply
dart run flutterl10 check
dart run flutterl10 gen
```

`dev_dependencies` is recommended because this is a development tool. Your app
does not need `flutterl10` at runtime.

## Optional Global Install

If you want shorter commands, you can activate it globally:

```bash
dart pub global activate --source git https://github.com/Parasgiri5637/flutterl10.git
```

Make sure Dart's global pub cache is in your `PATH`.

## Use in a Flutter Project

### 1. Add Flutter l10n support

In your Flutter app's `pubspec.yaml`, add localization dependencies and enable
code generation:

```yaml
dependencies:
  flutter:
    sdk: flutter
  flutter_localizations:
    sdk: flutter
  intl: any

flutter:
  generate: true
```

Then run:

```bash
flutter pub get
```

### 2. Add `l10n.yaml`

Create `l10n.yaml` in your Flutter project root:

```yaml
arb-dir: lib/l10n
template-arb-file: app_en.arb
output-localization-file: app_localizations.dart
```

### 3. Configure `MaterialApp`

Import generated localizations in your app:

```dart
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
```

Add localization delegates and supported locales:

```dart
MaterialApp(
  localizationsDelegates: const [
    AppLocalizations.delegate,
    GlobalMaterialLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
  ],
  supportedLocales: const [
    Locale('en'),
  ],
  home: const MyHomePage(),
)
```

### 4. Run `flutterl10`

Run these commands from your Flutter app root:

```bash
dart run flutterl10 scan
dart run flutterl10 apply
dart run flutterl10 check
dart run flutterl10 gen
```

Recommended first run:

```bash
dart run flutterl10 scan
dart run flutterl10 apply
dart run flutterl10 check
```

`apply` creates or updates `lib/l10n/app_en.arb`, replaces static UI text in
`lib`, and runs `flutter gen-l10n` by default.

If you installed globally, you can use the shorter command:

```bash
flutterl10 scan
flutterl10 apply
flutterl10 check
```

## Commands

### `flutterl10 scan`

Scans `lib/**/*.dart` and prints:

- total static texts found
- files scanned
- skipped or unsupported cases

### `flutterl10 apply`

Updates your Flutter app:

- reads `l10n.yaml` to find `arb-dir` when available
- otherwise uses `lib/l10n/app_en.arb`
- adds new strings to `app_en.arb`
- avoids duplicate ARB entries by reusing existing values
- replaces UI literals with `AppLocalizations.of(context)!.keyName`
- adds `import 'package:flutter_gen/gen_l10n/app_localizations.dart';`
- runs `flutter gen-l10n`

Disable automatic generation:

```bash
flutterl10 apply --no-gen
```

### `flutterl10 check`

Counts remaining static UI text in `lib`.

It exits with code `1` when static UI text remains, which makes it useful in CI:

```bash
flutterl10 check
```

### `flutterl10 gen`

Runs:

```bash
flutter gen-l10n
```

## Examples

Input:

```dart
Text("Hello")
```

Output:

```dart
Text(AppLocalizations.of(context)!.hello)
```

Input:

```dart
TextField(
  decoration: const InputDecoration(
    hintText: "Enter your email",
  ),
)
```

Output:

```dart
TextField(
  decoration: InputDecoration(
    hintText: AppLocalizations.of(context)!.enterYourEmail,
  ),
)
```

ARB:

```json
{
  "@@locale": "en",
  "enterYourEmail": "Enter your email",
  "hello": "Hello"
}
```

## Detection Coverage

The scanner detects common visible UI text patterns:

- `Text("Hello")`
- `SelectableText("Copy")`
- `RichText(text: TextSpan(text: "Terms"))`
- `TextSpan(text: "Terms")`
- `hintText: "Enter name"`
- `labelText: "Email"`
- `helperText`, `errorText`, `counterText`, `prefixText`, `suffixText`
- `tooltip`, `semanticLabel`, `semanticsLabel`
- `title`, `subtitle`, `label`, `message`, `barrierLabel`, `content`
- validator returns inside `validator` callbacks or validator methods
- simple indirect variables used in UI, for example `final title = "Home"; Text(title)`
- interpolation, for example `Text("Hello $name")`
- concatenation, for example `Text("Welcome " + name)`
- long UI text, with short generated key names

Interpolation and concatenation are written to ARB with placeholders:

```json
{
  "helloName": "Hello {name}",
  "@helloName": {
    "placeholders": {
      "name": {
        "type": "Object"
      }
    }
  }
}
```

Long text keeps the full English value in ARB, but the generated key is capped:

```json
{
  "thisIsAVeryLongStaticMessage3b2586": "This is a very long static message that explains..."
}
```

The scanner ignores strings that are not used in recognized UI contexts, such as:

- API URLs
- asset paths
- `print` and `debugPrint` messages
- constants that are not used by UI expressions

Unsupported cases are reported instead of guessed:

- multiline strings
- complex dynamic expressions that cannot safely become localization arguments
- custom widget parameters not listed in the UI property allowlist

## Options

```bash
flutterl10 scan --project-root /path/to/app
flutterl10 apply --arb-dir lib/l10n --arb-file app_en.arb
flutterl10 check --lib-dir lib
```

## Flutter l10n Setup

Your Flutter app should have localization enabled, usually with:

```yaml
flutter:
  generate: true
```

And dependencies similar to:

```yaml
dependencies:
  flutter_localizations:
    sdk: flutter
  intl: any
```

Optional `l10n.yaml`:

```yaml
arb-dir: lib/l10n
template-arb-file: app_en.arb
output-localization-file: app_localizations.dart
```
