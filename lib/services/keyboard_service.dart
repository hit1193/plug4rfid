import 'dart:io';
import 'dart:ffi'; // 🔥 sizeOf 사용을 위해 필수
import 'package:ffi/ffi.dart'; // 🔥 calloc, free 사용을 위해 필수
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
// 윈도우 OS 레벨의 이벤트를 제어하기 위한 패키지
import 'package:win32/win32.dart';

/// ---------------------------------------------------------------------------
/// [키보드 에뮬레이션 서비스 (KeyboardService)]
/// RFID 태그 데이터 등을 시스템의 키보드 입력 이벤트로 변환하여
/// 현재 포커스가 가 있는 모든 응용 프로그램(메모장, ERP 등)에 전달합니다.
/// ---------------------------------------------------------------------------
class KeyboardService {

  /// ---------------------------------------------------------------------------
  /// [텍스트 입력 시뮬레이션]
  /// 입력받은 문자열을 순차적으로 키보드 타이핑 이벤트로 변환합니다.
  /// ---------------------------------------------------------------------------
  static Future<void> sendTextAsKeys(String text) async {
    // 웹 환경에서는 브라우저 보안 정책상 시스템 키보드 직접 제어가 불가능합니다.
    if (kIsWeb) return;

    if (Platform.isWindows) {
      // 윈도우 데스크톱 환경에서는 Win32 API를 호출합니다.
      _sendWindowsInput(text);
    } else if (Platform.isAndroid) {
      // 안드로이드에서는 시스템 클립보드에 복사하여 붙여넣기를 유도하는 방식이 가장 안정적입니다.
      await Clipboard.setData(ClipboardData(text: text));
    }
  }

  /// ---------------------------------------------------------------------------
  /// [윈도우 전용 입력 전송 (Win32 API)]
  /// 윈도우 OS의 SendInput 함수를 사용하여 물리적인 키보드 입력을 시뮬레이션합니다.
  /// ---------------------------------------------------------------------------
  static void _sendWindowsInput(String text) {
    // 문자열을 순회하며 각 문자의 유니코드 값을 키보드 신호로 보냅니다.
    for (var i = 0; i < text.length; i++) {
      final charCode = text.codeUnitAt(i);

      // 1. 키 누름 이벤트 (KeyDown) 설정
      // calloc은 C의 malloc처럼 메모리를 할당하는 함수입니다.
      final Pointer<INPUT> inputDown = calloc<INPUT>();
      inputDown.ref.type = INPUT_KEYBOARD;
      inputDown.ref.ki.wScan = charCode;
      inputDown.ref.ki.dwFlags = KEYEVENTF_UNICODE;

      // OS에 신호 전송 (sizeOf는 구조체의 크기를 계산합니다.)
      SendInput(1, inputDown, sizeOf<INPUT>());
      free(inputDown); // 사용한 메모리는 즉시 해제합니다. (C++ 스타일)

      // 2. 키 뗌 이벤트 (KeyUp) 설정
      final Pointer<INPUT> inputUp = calloc<INPUT>();
      inputUp.ref.type = INPUT_KEYBOARD;
      inputUp.ref.ki.wScan = charCode;
      inputUp.ref.ki.dwFlags = KEYEVENTF_UNICODE | KEYEVENTF_KEYUP;

      SendInput(1, inputUp, sizeOf<INPUT>());
      free(inputUp);
    }

    // 데이터 입력 후 자동으로 엔터(Enter) 키를 전송하여 줄바꿈 처리를 합니다.
    _sendEnterKey();
  }

  /// 윈도우 OS 시스템 엔터 키 입력을 생성합니다.
  static void _sendEnterKey() {
    // Enter KeyDown
    final Pointer<INPUT> inputDown = calloc<INPUT>();
    inputDown.ref.type = INPUT_KEYBOARD;
    inputDown.ref.ki.wVk = VK_RETURN;
    SendInput(1, inputDown, sizeOf<INPUT>());
    free(inputDown);

    // Enter KeyUp
    final Pointer<INPUT> inputUp = calloc<INPUT>();
    inputUp.ref.type = INPUT_KEYBOARD;
    inputUp.ref.ki.wVk = VK_RETURN;
    inputUp.ref.ki.dwFlags = KEYEVENTF_KEYUP;
    SendInput(1, inputUp, sizeOf<INPUT>());
    free(inputUp);
  }
}