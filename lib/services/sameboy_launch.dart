import 'dart:io';

enum SameBoyHelper {
  live('sameboy-live', 'stream_sameboy'),
  preview('sameboy-preview', 'run_sameboy_frames'),
  gba('mgba-live', 'stream_mgba');

  const SameBoyHelper(this.binary, this.script);
  final String binary;
  final String script;
}

/// The portable layout is resolved from the host executable, even when the
/// launcher sets another working directory. Source checkouts retain dart run.
class SameBoyLaunch {
  SameBoyLaunch._(this.root, this.executable, this.prefix, this.usesShell);
  final Directory root;
  final String executable;
  final List<String> prefix;
  final bool usesShell;

  static SameBoyLaunch resolve(
    SameBoyHelper helper, {
    Directory? appDirectory,
    Directory? checkout,
  }) {
    final app = appDirectory ?? File(Platform.resolvedExecutable).parent;
    final portable = Directory('${app.path}/helpers').existsSync();
    final root = (portable ? app : checkout ?? Directory.current).absolute;
    final name = helper == SameBoyHelper.gba ? 'mGBA' : 'SameBoy';
    final core = File('${root.path}/cores/windows/${name.toLowerCase()}_libretro.dll');
    if (!core.existsSync()) {
      throw StateError('Núcleo $name ausente: ${core.path}');
    }
    if (portable) {
      final exe = File('${app.path}/helpers/${helper.binary}.exe');
      if (!exe.existsSync()) throw StateError('Auxiliar ausente: ${exe.path}');
      return SameBoyLaunch._(root, exe.absolute.path, const [], false);
    }
    final script = File('${root.path}/tool/${helper.script}.dart');
    if (!script.existsSync()) {
      throw StateError('Auxiliar de desenvolvimento ausente: ${script.path}');
    }
    return SameBoyLaunch._(root, 'dart', ['run', script.absolute.path], true);
  }
}
