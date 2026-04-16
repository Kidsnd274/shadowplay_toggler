import 'dart:ffi';
import 'dart:io';
import 'package:ffi/ffi.dart';

typedef _InitializeC = Int32 Function();
typedef _InitializeDart = int Function();

typedef _ShutdownC = Void Function();
typedef _ShutdownDart = void Function();

typedef _IsInitializedC = Int32 Function();
typedef _IsInitializedDart = int Function();

typedef _GetErrorMessageC = Pointer<Utf8> Function(Int32 status);
typedef _GetErrorMessageDart = Pointer<Utf8> Function(int status);

class BridgeFfi {
  late final DynamicLibrary _lib;

  late final _InitializeDart initialize;
  late final _ShutdownDart shutdown;
  late final _IsInitializedDart isInitialized;
  late final _GetErrorMessageDart _getErrorMessage;

  BridgeFfi() {
    final exeDir = File(Platform.resolvedExecutable).parent.path;
    _lib = DynamicLibrary.open('$exeDir/shadowplay_bridge.dll');

    initialize = _lib
        .lookupFunction<_InitializeC, _InitializeDart>('bridge_initialize');

    shutdown =
        _lib.lookupFunction<_ShutdownC, _ShutdownDart>('bridge_shutdown');

    isInitialized = _lib.lookupFunction<_IsInitializedC, _IsInitializedDart>(
        'bridge_is_initialized');

    _getErrorMessage =
        _lib.lookupFunction<_GetErrorMessageC, _GetErrorMessageDart>(
            'bridge_get_error_message');
  }

  String getErrorMessage(int status) {
    final ptr = _getErrorMessage(status);
    return ptr.toDartString();
  }
}
