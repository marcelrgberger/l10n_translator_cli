import 'dart:convert';
import 'dart:io';

import 'package:args/args.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

/// ------------------------------
/// Konfiguration & Hilfen
/// ------------------------------
class L10nConfig {
  final String arbDir;
  final String templateArbFile;
  final String outputLocalizationFile;
  final List<String> locales;

  L10nConfig({
    required this.arbDir,
    required this.templateArbFile,
    required this.outputLocalizationFile,
    required this.locales,
  });

  static L10nConfig fromYamlFile(File l10nYaml) {
    final doc = loadYaml(l10nYaml.readAsStringSync()) as YamlMap;

    String reqStr(String key) {
      final v = doc[key];
      if (v is! String || v.trim().isEmpty) {
        throw StateError('Fehlender oder leerer Schlüssel "$key" in l10n.yaml');
      }
      return v.trim();
    }

    final localesRaw = (doc['locales'] as String? ?? '').trim();
    final locales = localesRaw.isEmpty
        ? <String>[]
        : localesRaw
            .split(',')
            .map((s) => s.trim())
            .where((s) => s.isNotEmpty)
            .toList();

    return L10nConfig(
      arbDir: reqStr('arb-dir'),
      templateArbFile: reqStr('template-arb-file'),
      outputLocalizationFile: reqStr('output-localization-file'),
      locales: locales,
    );
  }
}

final _placeholderRegex = RegExp(r'\{[a-zA-Z0-9_]+\}');

/// Prüft, ob Wert übersetzbar ist (Strings ja; Metadatenblöcke @… nein)
bool _isTranslatableEntry(String key, dynamic value) {
  if (key.startsWith('@')) return false; // ARB-Metadaten
  return value is String;
}

/// Tiefes Mapping nur über String-Werte; andere Strukturen bleiben unverändert
Map<String, dynamic> _extractTranslatable(Map<String, dynamic> arb) {
  final out = <String, dynamic>{};
  arb.forEach((k, v) {
    if (_isTranslatableEntry(k, v)) {
      out[k] = v;
    }
  });
  return out;
}

/// Setzt übersetzte Strings in die ARB-Struktur zurück (nur Werte, keine @-Blöcke)
Map<String, dynamic> _mergeTranslations(
  Map<String, dynamic> originalArb,
  Map<String, dynamic> translatedValues,
) {
  final merged = Map<String, dynamic>.from(originalArb);
  translatedValues.forEach((k, v) {
    if (merged.containsKey(k) && _isTranslatableEntry(k, merged[k])) {
      merged[k] = v;
    }
  });
  return merged;
}

/// Ersetzt ggf. die locale im Dateinamen: app_de.arb -> app_en.arb.
/// Wenn keine `_ <locale> `.arb Endung gefunden wird, hängt er _xx an.
String _targetArbFileName(String templateName, String targetLocale) {
  final localePattern =
      RegExp(r'_(?:[a-zA-Z]{2}(?:_[A-Z]{2})?)\.arb$'); // _de.arb, _en_GB.arb
  if (localePattern.hasMatch(templateName)) {
    return templateName.replaceFirst(localePattern, '_$targetLocale.arb');
  }
  // Fallback: vor .arb einfügen
  if (templateName.endsWith('.arb')) {
    final base = templateName.substring(0, templateName.length - 4);
    return '${base}_$targetLocale.arb';
  }
  return 'app_$targetLocale.arb';
}

/// ------------------------------
/// OpenAI Call
/// ------------------------------
class OpenAITranslator {
  OpenAITranslator({http.Client? client}) : _client = client ?? http.Client();
  final http.Client _client;

  Future<Map<String, dynamic>> translate({
    required String apiKey,
    required String sourceLocale,
    required String targetLocale,
    required Map<String, dynamic> sourceArb,
    String? model,
  }) async {
    // Nur übersetzbare Einträge extrahieren
    final translatable = _extractTranslatable(sourceArb);

    // Input als Liste von {key, value, placeholders}
    final entries = translatable.entries.map((e) {
      final value = e.value as String;
      final placeholders = _placeholderRegex
          .allMatches(value)
          .map((m) => m.group(0))
          .whereType<String>()
          .toSet()
          .toList();
      return {
        'key': e.key,
        'value': value,
        'placeholders': placeholders,
      };
    }).toList();

    // System-/User-Prompt so, dass NUR Werte übersetzt werden
    final systemPrompt = '''
You are a professional software localization engine.
Return strict JSON. Keep JSON keys exactly as provided.
Do NOT translate JSON keys.
Preserve all ICU placeholders like {count}, {error}, {current}, {total}.
Preserve ellipsis characters (…) and newline escape sequences (\\n).
Do not add or remove placeholders, punctuation, or emoji.
Return only translated values; do not include commentary.
''';

    final userPrompt = {
      'source_locale': sourceLocale,
      'target_locale': targetLocale,
      'entries': entries,
    };

    // Aktuelle, robuste OpenAI HTTP-API (Completions-ähnlicher JSON-Antwortmodus)
    // Falls du ein anderes Modell willst, anpassen (z. B. "gpt-4o-mini").
    final uri = Uri.parse('https://api.openai.com/v1/chat/completions');
    final chosenModel = model ?? 'gpt-4o-mini';

    final body = jsonEncode({
      'model': chosenModel,
      'response_format': {'type': 'json_object'},
      'messages': [
        {'role': 'system', 'content': systemPrompt},
        {
          'role': 'user',
          'content':
              'Translate the following ARB entries. Return a JSON object with {"translations":[{"key":"...", "value":"..."}]}.'
        },
        {
          'role': 'user',
          'content': jsonEncode(userPrompt),
        }
      ],
      'temperature': 0.2,
    });

    final resp = await _client.post(
      uri,
      headers: {
        'Authorization': 'Bearer $apiKey',
        'Content-Type': 'application/json',
      },
      body: body,
    );

    if (resp.statusCode >= 300) {
      throw HttpException('OpenAI Error ${resp.statusCode}: ${resp.body}');
    }

    final decoded = jsonDecode(resp.body) as Map<String, dynamic>;
    final content =
        (decoded['choices'] as List).first['message']['content'] as String;
    final jsonOut = jsonDecode(content) as Map<String, dynamic>;

    final translations = (jsonOut['translations'] as List)
        .cast<Map<String, dynamic>>()
        .fold<Map<String, String>>({}, (acc, item) {
      final key = item['key'] as String;
      final value = item['value'] as String;
      acc[key] = value;
      return acc;
    });

    // Sicherheitscheck: Platzhalter müssen 1:1 vorhanden bleiben
    for (final entry in entries) {
      final k = entry['key'] as String;
      final originalPh = Set<String>.from(entry['placeholders'] as List);
      final tVal = translations[k] ?? '';
      final translatedPh = _placeholderRegex
          .allMatches(tVal)
          .map((m) => m.group(0))
          .whereType<String>()
          .toSet();
      if (originalPh.length != translatedPh.length ||
          !originalPh.containsAll(translatedPh)) {
        throw StateError(
          'Platzhalter-Mismatch bei Schlüssel "$k". Original: $originalPh, Übersetzt: $translatedPh',
        );
      }
    }

    // Baue Map key -> value zurück
    return translations.map((k, v) => MapEntry(k, v));
  }
}

/// ------------------------------
/// Haupt-CLI
/// ------------------------------
void main(List<String> args) async {
  final parser = ArgParser()
    ..addOption('config',
        abbr: 'c', help: 'Pfad zu l10n.yaml', defaultsTo: 'l10n.yaml')
    ..addOption('source-locale',
        help: 'Quellsprache des Templates (z.B. de)', defaultsTo: 'de')
    ..addOption('model',
        help: 'OpenAI-Modell (z.B. gpt-4o-mini)', defaultsTo: 'gpt-4o-mini')
    ..addFlag('dry-run',
        help: 'Nur anzeigen, nichts schreiben', defaultsTo: false)
    ..addMultiOption('only',
        help:
            'Nur diese Ziel-Locales übersetzen (überschreibt l10n.yaml locales). Mehrfach angeben.',
        valueHelp: 'en,fr,...');

  late ArgResults opts;
  try {
    opts = parser.parse(args);
  } catch (e) {
    stderr.writeln(e);
    stderr.writeln(parser.usage);
    exit(64);
  }

  final l10nPath = opts['config'] as String;
  final sourceLocale = opts['source-locale'] as String;
  final model = opts['model'] as String;
  final dryRun = opts['dry-run'] as bool;
  final only = (opts['only'] as List).cast<String>();

  final apiKey = Platform.environment['OPENAI_API_KEY'];
  if (apiKey == null || apiKey.isEmpty) {
    stderr.writeln('Fehlende Umgebungsvariable OPENAI_API_KEY.');
    exit(64);
  }

  final l10nFile = File(l10nPath);
  if (!l10nFile.existsSync()) {
    stderr.writeln('l10n.yaml nicht gefunden: $l10nPath');
    exit(66);
  }

  final cfg = L10nConfig.fromYamlFile(l10nFile);
  var targetLocales = only.isNotEmpty ? only : cfg.locales;
  if (targetLocales.isEmpty) {
    stderr.writeln(
        'Keine Ziel-Locales definiert (l10n.yaml "locales" oder --only).');
    exit(64);
  }
  targetLocales = targetLocales.where((l) => l != sourceLocale).toList();

  final arbDir = Directory(cfg.arbDir);
  if (!arbDir.existsSync()) {
    stderr.writeln('ARB-Verzeichnis nicht gefunden: ${cfg.arbDir}');
    exit(66);
  }

  final templateFile = File(p.join(cfg.arbDir, cfg.templateArbFile));
  if (!templateFile.existsSync()) {
    stderr.writeln('Template-ARB nicht gefunden: ${templateFile.path}');
    exit(66);
  }

  // ARB laden
  final templateJson =
      jsonDecode(templateFile.readAsStringSync()) as Map<String, dynamic>;

  final translator = OpenAITranslator();

  stdout.writeln('Template: ${templateFile.path}');
  stdout.writeln('Ziel-Locales: ${targetLocales.join(', ')}');

  for (final locale in targetLocales) {
    final targetName = _targetArbFileName(cfg.templateArbFile, locale);
    final targetPath = p.join(cfg.arbDir, targetName);
    stdout.writeln('→ Übersetze $sourceLocale → $locale  → $targetName');

    try {
      final translatedValues = await translator.translate(
        apiKey: apiKey,
        sourceLocale: sourceLocale,
        targetLocale: locale,
        sourceArb: templateJson,
        model: model,
      );

      final merged = _mergeTranslations(templateJson, translatedValues);

      // locale im ARB setzen
      merged['@@locale'] = locale;

      final outJson = const JsonEncoder.withIndent('  ').convert(merged);

      if (dryRun) {
        stdout.writeln('DRY-RUN: Würde schreiben: $targetPath');
      } else {
        File(targetPath).writeAsStringSync('$outJson\n');
        stdout.writeln('✓ Geschrieben: $targetPath');
      }
    } on Exception catch (e) {
      stderr.writeln('FEHLER bei $locale: $e');
      // Nicht abbrechen – nächste Sprache versuchen
    }
  }

  stdout.writeln('Fertig.');
}
