import 'dart:convert';
import 'dart:io';

class SdkOpts {
  const SdkOpts({
    required this.ccArgs,
    required this.cppArgs,
    required this.linkerArgs,
    required this.linkerLibs,
    required this.sdkSymbols,
    required this.hardware,
  });

  final List<String> ccArgs;
  final List<String> cppArgs;
  final List<String> linkerArgs;
  final List<String> linkerLibs;
  final String sdkSymbols;
  final String hardware;

  static const Set<String> splitVars = {
    'cc_args',
    'cpp_args',
    'linker_args',
    'linker_libs',
  };

  static SdkOpts load(
    Directory sdkHeadersDir, {
    required String appEntry,
    required String mapFile,
  }) {
    final file = File('${sdkHeadersDir.path}${Platform.pathSeparator}sdk.opts');
    final json = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;

    final replacements = <String, String>{
      json['app_ep_subst'] as String: appEntry,
      json['sdk_path_subst'] as String: sdkHeadersDir.absolute.path.replaceAll(
        r'\',
        '/',
      ),
      json['map_file_subst'] as String: mapFile,
    };

    String substitute(String value) {
      var result = value;
      replacements.forEach((from, to) => result = result.replaceAll(from, to));
      return result;
    }

    List<String> split(String key) =>
        splitArguments(substitute(json[key] as String? ?? ''));

    return SdkOpts(
      ccArgs: split('cc_args'),
      cppArgs: split('cpp_args'),
      linkerArgs: split('linker_args'),
      linkerLibs: split('linker_libs'),
      sdkSymbols: substitute(json['sdk_symbols'] as String? ?? ''),
      hardware: '${json['hardware']}',
    );
  }

  static List<String> splitArguments(String value) => value
      .split(RegExp(r'\s+'))
      .where((token) => token.isNotEmpty)
      .map(unquote)
      .toList();

  static String unquote(String token) {
    final buffer = StringBuffer();
    String? quote;
    for (var i = 0; i < token.length; i++) {
      final c = token[i];
      if (c == r'\' && i + 1 < token.length && quote != "'") {
        buffer.write(token[++i]);
      } else if (quote == null && (c == '"' || c == "'")) {
        quote = c;
      } else if (quote == c) {
        quote = null;
      } else {
        buffer.write(c);
      }
    }
    return buffer.toString();
  }
}
