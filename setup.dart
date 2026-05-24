// ignore_for_file: avoid_print

import 'dart:convert';
import 'dart:io';

String get _current => Directory.current.path;

String pathJoin(String p1, String p2, [String? p3, String? p4, String? p5]) {
  final sep = Platform.pathSeparator;
  final buffer = StringBuffer(p1);
  for (final part in [p2, p3, p4, p5]) {
    if (part == null) break;
    if (!buffer.toString().endsWith(sep) && !part.startsWith(sep)) {
      buffer.write(sep);
    }
    buffer.write(part);
  }
  return buffer.toString();
}

String pathBasename(String path) {
  return path.split(Platform.pathSeparator).last;
}

enum Target { windows, linux, android, macos }

extension TargetExt on Target {
  String get os {
    if (this == Target.macos) {
      return 'darwin';
    }
    return name;
  }

  bool get same {
    if (this == Target.android) {
      return true;
    }
    if (Platform.isWindows && this == Target.windows) {
      return true;
    }
    if (Platform.isLinux && this == Target.linux) {
      return true;
    }
    if (Platform.isMacOS && this == Target.macos) {
      return true;
    }
    return false;
  }

  String get dynamicLibExtensionName {
    final String extensionName;
    switch (this) {
      case Target.android || Target.linux:
        extensionName = '.so';
        break;
      case Target.windows:
        extensionName = '.dll';
        break;
      case Target.macos:
        extensionName = '.dylib';
        break;
    }
    return extensionName;
  }

  String get executableExtensionName {
    final String extensionName;
    switch (this) {
      case Target.windows:
        extensionName = '.exe';
        break;
      default:
        extensionName = '';
        break;
    }
    return extensionName;
  }
}

enum Mode { core, lib }

enum Arch { amd64, arm64, arm }

class BuildItem {
  Target target;
  Arch? arch;
  String? archName;

  BuildItem({required this.target, this.arch, this.archName});

  @override
  String toString() {
    return 'BuildLibItem{target: $target, arch: $arch, archName: $archName}';
  }
}

class Build {
  static List<BuildItem> get buildItems => [
    BuildItem(target: Target.macos, arch: Arch.arm64),
    BuildItem(target: Target.macos, arch: Arch.amd64),
    BuildItem(target: Target.linux, arch: Arch.arm64),
    BuildItem(target: Target.linux, arch: Arch.amd64),
    BuildItem(target: Target.windows, arch: Arch.amd64),
    BuildItem(target: Target.windows, arch: Arch.arm64),
    BuildItem(target: Target.android, arch: Arch.arm, archName: 'armeabi-v7a'),
    BuildItem(target: Target.android, arch: Arch.arm64, archName: 'arm64-v8a'),
    BuildItem(target: Target.android, arch: Arch.amd64, archName: 'x86_64'),
  ];

  static String get appName => 'FlClash';

  static String get coreName => 'FlClashCore';

  static String get libName => 'libclash';

  static String get outDir => pathJoin(_current, libName);

  static String get _coreDir => pathJoin(_current, 'core');

  static String get _servicesDir => pathJoin(_current, 'services', 'helper');

  static String get distPath => pathJoin(_current, 'dist');

  static String _getCc(BuildItem buildItem) {
    final environment = Platform.environment;
    if (buildItem.target == Target.android) {
      final ndk = environment['ANDROID_NDK'];
      assert(ndk != null);
      final prebuiltDir = Directory(
        pathJoin(ndk!, 'toolchains', 'llvm', 'prebuilt'),
      );
      final prebuiltDirList = prebuiltDir
          .listSync()
          .where((file) => !pathBasename(file.path).startsWith('.'))
          .toList();
      final map = {
        'armeabi-v7a': 'armv7a-linux-androideabi21-clang',
        'arm64-v8a': 'aarch64-linux-android21-clang',
        'x86': 'i686-linux-android21-clang',
        'x86_64': 'x86_64-linux-android21-clang',
      };
      return pathJoin(prebuiltDirList.first.path, 'bin', map[buildItem.archName]);
    }
    return 'gcc';
  }

  static String get tags => 'with_gvisor';

  static Future<void> exec(
    List<String> executable, {
    String? name,
    Map<String, String>? environment,
    String? workingDirectory,
    bool runInShell = true,
  }) async {
    if (name != null) print('run $name');
    print('exec: ${executable.join(' ')}');
    print('env: ${environment.toString()}');
    final process = await Process.start(
      executable[0],
      executable.sublist(1),
      environment: environment,
      workingDirectory: workingDirectory,
      runInShell: runInShell,
    );
    process.stdout.listen((data) {
      print(utf8.decode(data));
    });
    process.stderr.listen((data) {
      print(utf8.decode(data));
    });
    final exitCode = await process.exitCode;
    if (exitCode != 0 && name != null) throw '$name error';
  }

  static Future<String> calcSha256(String filePath) async {
    final file = File(filePath);
    if (!await file.exists()) {
      throw 'File not exists';
    }
    if (Platform.isWindows) {
      final result = await Process.run('certutil', [
        '-hashfile',
        filePath,
        'SHA256',
      ]);
      return result.stdout.toString().split('\n').skip(1).first.trim();
    } else {
      final result = await Process.run('sha256sum', [filePath]);
      return result.stdout.toString().split(' ').first.trim();
    }
  }

  static Future<List<String>> buildCore({
    required Mode mode,
    required Target target,
    Arch? arch,
  }) async {
    final isLib = mode == Mode.lib;

    final items = buildItems.where((element) {
      return element.target == target &&
          (arch == null ? true : element.arch == arch);
    }).toList();

    final List<String> corePaths = [];

    final targetOutFilePath = pathJoin(outDir, target.name);
    final targetOutFile = File(targetOutFilePath);
    if (await targetOutFile.exists()) {
      await targetOutFile.delete(recursive: true);
      await Directory(targetOutFilePath).create(recursive: true);
    }
    for (final item in items) {
      final outFilePath = pathJoin(targetOutFilePath, item.archName ?? '');
      final file = File(outFilePath);
      if (file.existsSync()) {
        file.deleteSync(recursive: true);
      }

      final fileName = isLib
          ? '$libName${item.target.dynamicLibExtensionName}'
          : '$coreName${item.target.executableExtensionName}';
      final realOutPath = pathJoin(outFilePath, fileName);
      corePaths.add(realOutPath);

      final Map<String, String> env = {};
      env['GOOS'] = item.target.os;
      if (item.arch != null) {
        env['GOARCH'] = item.arch!.name;
      }
      if (isLib) {
        env['CGO_ENABLED'] = '1';
        env['CC'] = _getCc(item);
        env['CFLAGS'] = '-O3 -Werror';
      } else {
        env['CGO_ENABLED'] = '0';
      }
      final execLines = [
        'go',
        'build',
        '-ldflags=-w -s',
        '-tags=$tags',
        if (isLib) '-buildmode=c-shared',
        '-o',
        realOutPath,
      ];
      await exec(
        execLines,
        name: 'build core',
        environment: env,
        workingDirectory: _coreDir,
      );
      if (isLib && item.archName != null) {
        await adjustLibOut(
          targetOutFilePath: targetOutFilePath,
          outFilePath: outFilePath,
          archName: item.archName!,
        );
      }
    }

    return corePaths;
  }

  static Future<void> adjustLibOut({
    required String targetOutFilePath,
    required String outFilePath,
    required String archName,
  }) async {
    final includesPath = pathJoin(targetOutFilePath, 'includes');
    final realOutPath = pathJoin(includesPath, archName);
    await Directory(realOutPath).create(recursive: true);
    final targetOutFiles = Directory(outFilePath).listSync();
    final coreFiles = Directory(_coreDir).listSync();
    for (final file in [...targetOutFiles, ...coreFiles]) {
      if (!file.path.endsWith('.h')) {
        continue;
      }
      final targetFilePath = pathJoin(realOutPath, pathBasename(file.path));
      final realFile = File(file.path);
      await realFile.copy(targetFilePath);
      if (coreFiles.contains(file)) {
        continue;
      }
      await realFile.delete();
    }
  }

  static Future<void> buildHelper(Target target, String token) async {
    await exec(
      ['cargo', 'build', '--release', '--features', 'windows-service'],
      environment: {'TOKEN': token},
      name: 'build helper',
      workingDirectory: _servicesDir,
    );
    final outPath = pathJoin(
      _servicesDir,
      'target',
      'release',
      'helper${target.executableExtensionName}',
    );
    final targetPath = pathJoin(
      outDir,
      target.name,
      'FlClashHelperService${target.executableExtensionName}',
    );
    await File(outPath).copy(targetPath);
  }

  static List<String> getExecutable(String command) {
    return command.split(' ');
  }

  static Future<void> getDistributor() async {
    final distributorDir = pathJoin(
      _current,
      'plugins',
      'flutter_distributor',
      'packages',
      'flutter_distributor',
    );

    await exec(
      name: 'clean distributor',
      Build.getExecutable('flutter clean'),
      workingDirectory: distributorDir,
    );
    await exec(
      name: 'upgrade distributor',
      Build.getExecutable('flutter pub upgrade'),
      workingDirectory: distributorDir,
    );
    await exec(
      name: 'get distributor',
      Build.getExecutable('dart pub global activate -s path $distributorDir'),
    );
  }

  static void copyFile(String sourceFilePath, String destinationFilePath) {
    final sourceFile = File(sourceFilePath);
    if (!sourceFile.existsSync()) {
      throw 'SourceFilePath not exists';
    }
    final destinationFile = File(destinationFilePath);
    final destinationDirectory = destinationFile.parent;
    if (!destinationDirectory.existsSync()) {
      destinationDirectory.createSync(recursive: true);
    }
    try {
      sourceFile.copySync(destinationFilePath);
      print('File copied successfully!');
    } catch (e) {
      print('Failed to copy file: $e');
    }
  }
}

class BuildCommand {
  Target target;
  String? archArg;
  String? outArg;
  String? envArg;

  BuildCommand({
    required this.target,
    this.archArg,
    this.outArg,
    this.envArg,
  });

  String get name => target.name;

  List<Arch> get arches => Build.buildItems
      .where((element) => element.target == target && element.arch != null)
      .map((e) => e.arch!)
      .toList();

  Future<void> _buildEnvFile(String env, {String? coreSha256}) async {
    final data = {
      'APP_ENV': env,
      if (coreSha256 != null) 'CORE_SHA256': coreSha256,
    };
    final envFile = File(pathJoin(_current, 'env.json'))..create();
    await envFile.writeAsString(json.encode(data));
  }

  Future<void> _getLinuxDependencies(Arch arch) async {
    await Build.exec(Build.getExecutable('sudo apt update -y'));
    await Build.exec(
      Build.getExecutable('sudo apt install -y ninja-build libgtk-3-dev'),
    );
    await Build.exec(
      Build.getExecutable('sudo apt install -y libayatana-appindicator3-dev'),
    );
    await Build.exec(
      Build.getExecutable('sudo apt-get install -y libkeybinder-3.0-dev'),
    );
    await Build.exec(Build.getExecutable('sudo apt install -y locate'));
    if (arch == Arch.amd64) {
      await Build.exec(Build.getExecutable('sudo apt install -y rpm patchelf'));
      await Build.exec(Build.getExecutable('sudo apt install -y libfuse2'));

      final downloadName = arch == Arch.amd64 ? 'x86_64' : 'aarch64';
      await Build.exec(
        Build.getExecutable(
          'wget -O appimagetool https://github.com/AppImage/AppImageKit/releases/download/continuous/appimagetool-$downloadName.AppImage',
        ),
      );
      await Build.exec(Build.getExecutable('chmod +x appimagetool'));
      await Build.exec(
        Build.getExecutable('sudo mv appimagetool /usr/local/bin/'),
      );
    }
  }

  Future<void> _getMacosDependencies() async {
    await Build.exec(Build.getExecutable('npm install -g appdmg'));
  }

  Future<void> _buildDistributor({
    required Target target,
    required String targets,
    String args = '',
    required String env,
  }) async {
    await Build.getDistributor();
    await Build.exec(
      name: name,
      Build.getExecutable(
        'flutter_distributor package --skip-clean --platform ${target.name} --targets $targets --flutter-build-args=verbose,dart-define-from-file=env.json$args',
      ),
    );
  }

  Future<String?> get systemArch async {
    if (Platform.isWindows) {
      return Platform.environment['PROCESSOR_ARCHITECTURE'];
    } else if (Platform.isLinux || Platform.isMacOS) {
      final result = await Process.run('uname', ['-m']);
      return result.stdout.toString().trim();
    }
    return null;
  }

  Future<void> run() async {
    final mode = target == Target.android ? Mode.lib : Mode.core;
    final String out = outArg ?? (target.same ? 'app' : 'core');
    final archName = archArg;
    final env = envArg ?? 'pre';
    final currentArches = arches
        .where((element) => element.name == archName)
        .toList();
    final arch = currentArches.isEmpty ? null : currentArches.first;

    if (arch == null && target != Target.android) {
      throw 'Invalid arch parameter';
    }

    final corePaths = await Build.buildCore(
      target: target,
      arch: arch,
      mode: mode,
    );

    String? coreSha256;

    if (Platform.isWindows) {
      coreSha256 = await Build.calcSha256(corePaths.first);
      await Build.buildHelper(target, coreSha256);
    }
    await _buildEnvFile(env, coreSha256: coreSha256);
    if (out != 'app') {
      return;
    }

    switch (target) {
      case Target.windows:
        _buildDistributor(
          target: target,
          targets: 'exe,zip',
          args: ' --description $archName',
          env: env,
        );
        return;
      case Target.linux:
        final targetMap = {Arch.arm64: 'linux-arm64', Arch.amd64: 'linux-x64'};
        final targets = [
          'deb',
          if (arch == Arch.amd64) 'appimage',
          if (arch == Arch.amd64) 'rpm',
        ].join(',');
        final defaultTarget = targetMap[arch];
        await _getLinuxDependencies(arch!);
        _buildDistributor(
          target: target,
          targets: targets,
          args:
              ' --description $archName --build-target-platform $defaultTarget',
          env: env,
        );
        return;
      case Target.android:
        final targetMap = {
          Arch.arm: 'android-arm',
          Arch.arm64: 'android-arm64',
          Arch.amd64: 'android-x64',
        };
        final defaultArches = [Arch.arm, Arch.arm64, Arch.amd64];
        final defaultTargets = defaultArches
            .where((element) => arch == null ? true : element == arch)
            .map((e) => targetMap[e])
            .toList();
        _buildDistributor(
          target: target,
          targets: 'apk',
          args:
              ",split-per-abi --build-target-platform ${defaultTargets.join(",")}",
          env: env,
        );
        return;
      case Target.macos:
        await _getMacosDependencies();
        _buildDistributor(
          target: target,
          targets: 'dmg',
          args: ' --description $archName',
          env: env,
        );
        return;
    }
  }
}

Future<void> main(List<String> args) async {
  if (args.isEmpty) {
    print('Usage: dart setup.dart <target> [--arch <arch>] [--out <out>] [--env <env>]');
    print('Targets: android, linux, windows, macos');
    return;
  }

  final targetName = args[0];
  final target = Target.values.firstWhere(
    (t) => t.name == targetName,
    orElse: () => throw 'Invalid target: $targetName. Valid: android, linux, windows, macos',
  );

  String? archValue;
  String? outValue;
  String? envValue;

  for (var i = 1; i < args.length; i++) {
    switch (args[i]) {
      case '--arch':
        archValue = args[++i];
        break;
      case '--out':
        outValue = args[++i];
        break;
      case '--env':
        envValue = args[++i];
        break;
    }
  }

  final command = BuildCommand(
    target: target,
    archArg: archValue,
    outArg: outValue,
    envArg: envValue,
  );
  await command.run();
}
