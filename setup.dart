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

// === 配置加载（从 app_config.json）===
Map<String, dynamic>? _buildConfig;

Future<void> _loadBuildConfig() async {
  final configFile = File(pathJoin(_current, 'app_config.json'));
  if (await configFile.exists()) {
    final jsonStr = await configFile.readAsString();
    _buildConfig = json.decode(jsonStr) as Map<String, dynamic>;
    print('Config loaded: ${_buildConfig!['appName']}');
  } else {
    _buildConfig = {};
    print('Warning: app_config.json not found, using defaults');
  }
}

String get _appName => _buildConfig?['appName'] as String? ?? 'FlClash';
String get _coreName => _buildConfig?['coreName'] as String? ?? 'FlClashCore';
String get _helperName => _buildConfig?['helperName'] as String? ?? 'FlClashHelperService';
String get _appId => _buildConfig?['appId'] as String? ?? '728B3532-C74B-4870-9068-BE70FE12A3E6';
String get _packageName => _buildConfig?['packageName'] as String? ?? 'com.follow.clash';
Map<String, dynamic> get _features => _buildConfig?['features'] as Map<String, dynamic>? ?? {};

Future<String> _detectCurrentAppName() async {
  // 从 constant.dart 中读取当前的 appName
  final file = File(pathJoin(_current, 'lib', 'common', 'constant.dart'));
  if (await file.exists()) {
    final content = await file.readAsString();
    final reg = RegExp(r"const appName = '([^']+)'");
    final match = reg.firstMatch(content);
    if (match != null) return match.group(1)!;
  }
  return 'FlClash'; // 默认值
}

Future<String> _detectCurrentHelperName() async {
  final file = File(pathJoin(_current, 'lib', 'common', 'constant.dart'));
  if (await file.exists()) {
    final content = await file.readAsString();
    final reg = RegExp(r"const appHelperService = '([^']+)'");
    final match = reg.firstMatch(content);
    if (match != null) return match.group(1)!;
  }
  return 'FlClashHelperService';
}

Future<String> _detectCurrentCoreName() async {
  // 从 path.dart 中检测当前 core 文件名
  final file = File(pathJoin(_current, 'lib', 'common', 'path.dart'));
  if (await file.exists()) {
    final content = await file.readAsString();
    final reg = RegExp(r"join\(executableDirPath, '(.+)Core");
    final match = reg.firstMatch(content);
    if (match != null) return '${match.group(1)}Core';
  }
  return 'FlClashCore';
}

Future<String> _detectCurrentPackageName() async {
  // 从 android/app/build.gradle.kts 中检测当前包名
  final file = File(pathJoin(_current, 'android', 'app', 'build.gradle.kts'));
  if (await file.exists()) {
    final content = await file.readAsString();
    final reg = RegExp(r'applicationId = "([^"]+)"');
    final match = reg.firstMatch(content);
    if (match != null) return match.group(1)!;
  }
  return 'com.follow.clash';
}

Future<void> _syncNames() async {
  final appName = _appName;
  final coreName = _coreName;
  final helperName = _helperName;

  // 检测当前文件中已有的旧名称
  final oldAppName = await _detectCurrentAppName();
  final oldHelperName = await _detectCurrentHelperName();
  final oldCoreName = await _detectCurrentCoreName();
  final oldPackageName = await _detectCurrentPackageName();
  final oldAppNameLower = oldAppName.toLowerCase();

  print('=== Syncing names from app_config.json ===');
  print('  oldName=$oldAppName → newName=$appName');
  print('  oldCore=$oldCoreName → newCore=$coreName');
  print('  oldHelper=$oldHelperName → newHelper=$helperName');

  // 替换辅助：用检测到的旧名称替换硬编码的 FlClash
  String p(String pattern) => pattern.replaceAll('FlClash', oldAppName);
  String pCore(String pattern) => pattern.replaceAll('FlClashCore', oldCoreName);
  String pHelper(String pattern) => pattern.replaceAll('FlClashHelperService', oldHelperName);

  final tasks = <(String, List<(String, String)>)>[
    // windows/CMakeLists.txt
    (pathJoin(_current, 'windows', 'CMakeLists.txt'), [
      // ⚠️ 不替换 project(FlClash ...) — CMake target 名必须保持 FlClash
      (p('set(BINARY_NAME "FlClash")'), 'set(BINARY_NAME "$appName")'),
      (p('/FlClashCore.exe"'), '/$coreName.exe"'),
      (p('/FlClashHelperService.exe"'), '/$helperName.exe"'),
      // install 段落 - 不同格式
      ('"\${CLASH_DIR}/$oldCoreName.exe"', '"\${CLASH_DIR}/$coreName.exe"'),
      ('"\${CLASH_DIR}/$oldHelperName.exe"', '"\${CLASH_DIR}/$helperName.exe"'),
    ]),
    // windows/runner/Runner.rc
    (pathJoin(_current, 'windows', 'runner', 'Runner.rc'), [
      (p('VALUE "FileDescription", "FlClash"'), 'VALUE "FileDescription", "$appName"'),
      (p('VALUE "OriginalFilename", "FlClash.exe"'), 'VALUE "OriginalFilename", "$appName.exe"'),
      ('VALUE "ProductName", "clash"', 'VALUE "ProductName", "$appName"'),
      ('VALUE "InternalName", "clash"', 'VALUE "InternalName", "$appName"'),
      ('VALUE "ProductName", "$oldAppName"', 'VALUE "ProductName", "$appName"'),
      ('VALUE "InternalName", "$oldAppName"', 'VALUE "InternalName", "$appName"'),
    ]),
    // windows/runner/main.cpp
    (pathJoin(_current, 'windows', 'runner', 'main.cpp'), [
      (p('window.Create(L"FlClash"'), 'window.Create(L"$appName"'),
    ]),
    // make_config.yaml
    (pathJoin(_current, 'windows', 'packaging', 'exe', 'make_config.yaml'), [
      ('app_id: 728B3532-C74B-4870-9068-BE70FE12A3E6', 'app_id: $_appId'),
      (p('app_name: FlClash'), 'app_name: $appName'),
      (p('display_name: FlClash'), 'display_name: $appName'),
      (p('executable_name: FlClash.exe'), 'executable_name: $appName.exe'),
      (p('output_base_file_name: FlClash.exe'), 'output_base_file_name: $appName.exe'),
      ('publisher: $oldAppName', 'publisher: $appName'),
    ]),
    // distribute_options.yaml
    (pathJoin(_current, 'distribute_options.yaml'), [
      (p("app_name: 'FlClash'"), "app_name: '$appName'"),
    ]),
    // inno_setup.iss
    (pathJoin(_current, 'windows', 'packaging', 'exe', 'inno_setup.iss'), [
      // 注意：手动拼接 old 字符串，因为 helper 名不含 "Service" 后缀
      ("['$oldAppName.exe', '$oldCoreName.exe', '$oldHelperName.exe']",
       "['$appName.exe', '$coreName.exe', '$helperName.exe']"),
    ]),
    // lib/common/path.dart
    (pathJoin(_current, 'lib', 'common', 'path.dart'), [
      (pCore("FlClashCore\$executableExtension'"), "$coreName\$executableExtension'"),
      (p("'FlClash.lock'"), "'\$appName.lock'"),
    ]),
    // lib/common/constant.dart
    (pathJoin(_current, 'lib', 'common', 'constant.dart'), [
      (p("const appName = 'FlClash'"), "const appName = '$appName'"),
      (p("'/tmp/FlClashSocket_"), "'/tmp/${appName}Socket_"),
      (p("'FlClashMainIsolate'"), "'${appName}MainIsolate'"),
      (p("'FlClashServiceIsolate'"), "'${appName}ServiceIsolate'"),
      (pHelper("'FlClashHelperService'"), "'$helperName'"),
      // ⚠️ packageName 不随 app_config 更改，需与 Kotlin 源码目录结构一致
    ]),
    // services/helper/src/service/windows.rs
    (pathJoin(pathJoin(_current, 'services', 'helper', 'src', 'service'), 'windows.rs'), [
      (pHelper('"FlClashHelperService"'), '"$helperName"'),
    ]),
    // linux/CMakeLists.txt
    (pathJoin(_current, 'linux', 'CMakeLists.txt'), [
      (p('set(BINARY_NAME "FlClash")'), 'set(BINARY_NAME "$appName"'),
      (pCore('FlClashCore"'), '$coreName"'),
      ('set(BINARY_NAME "$oldAppName"', 'set(BINARY_NAME "$appName"'),
    ]),
    // linux/runner/my_application.cc
    (pathJoin(_current, 'linux', 'runner', 'my_application.cc'), [
      (p('gtk_header_bar_set_title(header_bar, "FlClash")'),
       'gtk_header_bar_set_title(header_bar, "$appName")'),
      (p('gtk_window_set_title(window, "FlClash")'),
       'gtk_window_set_title(window, "$appName")'),
    ]),
    // macos/Runner/Info.plist
    (pathJoin(_current, 'macos', 'Runner', 'Info.plist'), [
      (p('<key>CFBundleExecutable</key>\n\t<string>FlClash</string>'),
       '<key>CFBundleExecutable</key>\n\t<string>$appName</string>'),
      (p('<key>CFBundleName</key>\n\t<string>FlClash</string>'),
       '<key>CFBundleName</key>\n\t<string>$appName</string>'),
    ]),
    // lib/common/window.dart
    (pathJoin(_current, 'lib', 'common', 'window.dart'), [
      (p("protocol.register('flclash')"), "protocol.register('${appName.toLowerCase()}')"),
      ("protocol.register('$oldAppNameLower')", "protocol.register('${appName.toLowerCase()}')"),
    ]),
    // core/tun/tun.go
    (pathJoin(_current, 'core', 'tun', 'tun.go'), [
      (p('Device:              "FlClash"'), 'Device:              "$appName"'),
    ]),
    // android/app/build.gradle.kts
    (pathJoin(_current, 'android', 'app', 'build.gradle.kts'), [
      // ⚠️ 只改 applicationId，namespace 必须与源码目录结构一致
      ('applicationId = "com.follow.clash"', 'applicationId = "$_packageName"'),
      ('applicationId = "$oldPackageName"', 'applicationId = "$_packageName"'),
    ]),
    // android/app/src/main/AndroidManifest.xml
    (pathJoin(pathJoin(_current, 'android', 'app', 'src', 'main'), 'AndroidManifest.xml'), [
      (p('android:label="FlClash"'), 'android:label="$appName"'),
    ]),
    // android/app/src/debug/AndroidManifest.xml
    (pathJoin(pathJoin(_current, 'android', 'app', 'src', 'debug'), 'AndroidManifest.xml'), [
      (p('android:label="FlClash Debug"'), 'android:label="$appName Debug"'),
    ]),
    // android/common/src/main/java/.../GlobalState.kt
    (pathJoin(pathJoin(pathJoin(_current, 'android', 'common', 'src', 'main'), 'java', 'com', 'follow', 'clash'), 'common', 'GlobalState.kt'), [
      (p('NOTIFICATION_CHANNEL = "FlClash"'), 'NOTIFICATION_CHANNEL = "$appName"'),
    ]),
    // android/service/src/main/java/.../VpnService.kt
    (pathJoin(pathJoin(pathJoin(_current, 'android', 'service', 'src', 'main'), 'java', 'com', 'follow', 'clash'), 'service', 'VpnService.kt'), [
      (p('setSession("FlClash")'), 'setSession("$appName")'),
    ]),
    // android/service/src/main/java/.../NotificationModule.kt
    (pathJoin(pathJoin(pathJoin(_current, 'android', 'service', 'src', 'main'), 'java', 'com', 'follow', 'clash'), 'service', 'modules', 'NotificationModule.kt'), [
      (p('setContentTitle("FlClash")'), 'setContentTitle("$appName")'),
    ]),
    // android/service/src/main/java/.../NotificationParams.kt
    (pathJoin(pathJoin(pathJoin(_current, 'android', 'service', 'src', 'main'), 'java', 'com', 'follow', 'clash'), 'service', 'models', 'NotificationParams.kt'), [
      (p('val title: String = "FlClash"'), 'val title: String = "$appName"'),
    ]),
  ];

  // 生成功能开关文件
  await _generateFeatureFlags();

  for (final (filePath, pairs) in tasks) {
    final file = File(filePath);
    if (!await file.exists()) {
      print('  [SKIP] ${pathBasename(filePath)} (not found)');
      continue;
    }
    var content = await file.readAsString();
    var changed = false;
    for (final (oldStr, newStr) in pairs) {
      if (content.contains(oldStr)) {
        content = content.replaceAll(oldStr, newStr);
        changed = true;
      }
    }
    if (changed) {
      await file.writeAsString(content);
      print('  [OK] ${pathBasename(filePath)}');
    } else {
      print('  [--] ${pathBasename(filePath)} (already up to date)');
    }
  }
  print('=== Name sync complete ===');
}

Future<void> _generateFeatureFlags() async {
  final features = _features;
  final buffer = StringBuffer();
  buffer.writeln('// 由 setup.dart _syncNames() 自动生成，请勿手动修改');
  buffer.writeln('// 功能开关，控制 UI 控件的显隐\n');
  buffer.writeln('class FeatureFlags {');
  for (final entry in features.entries) {
    final key = entry.key;
    final value = entry.value;
    if (value is bool) {
      buffer.writeln('  /// $key\n  static const bool $key = $value;\n');
    }
  }
  buffer.writeln('}');
  final file = File(pathJoin(_current, 'lib', 'common', 'feature_flags.dart'));
  await file.writeAsString(buffer.toString());
  print('  [GEN] lib/common/feature_flags.dart');
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

  static String get appName => _appName;

  static String get coreName => _coreName;

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
      print(utf8.decode(data, allowMalformed: true));
    });
    process.stderr.listen((data) {
      print(utf8.decode(data, allowMalformed: true));
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
      '$_helperName${target.executableExtensionName}',
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
      'CORE_SHA256': ?coreSha256,
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
    if (target == Target.android && arch == null) {
      throw 'Android requires --arch parameter: arm64, arm, or amd64';
    }

    // 清理 CMake 缓存和 jniLibs，防止缓存污染导致构建失败
    if (target == Target.android) {
      final androidCoreDir = pathJoin(_current, 'android', 'core');
      final dirsToClean = [
        pathJoin(androidCoreDir, '.cxx'),
        pathJoin(androidCoreDir, 'src', 'main', 'jniLibs'),
      ];
      for (final dir in dirsToClean) {
        final d = Directory(dir);
        if (await d.exists()) {
          await d.delete(recursive: true);
        }
      }
    }

    final corePaths = await Build.buildCore(
      target: target,
      arch: arch,
      mode: mode,
    );

    String? coreSha256;

    if (Platform.isWindows && target == Target.windows) {
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
          Arch.arm: 'arm',
          Arch.arm64: 'arm64',
          Arch.amd64: 'x64',
        };
        final archTarget = arch != null ? targetMap[arch] : 'arm64';
        await Build.exec(
          name: 'build flutter apk',
          Build.getExecutable(
            'flutter build apk --release --split-per-abi --target-platform android-$archTarget --dart-define-from-file=env.json',
          ),
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
  await _loadBuildConfig();
  await _syncNames();

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
