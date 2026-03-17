import 'dart:convert';
import 'dart:async';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart'; // 🔥 로컬 환경설정(API키) 로드용
import '../models/user_model.dart';
import '../models/product_model.dart';

/// ---------------------------------------------------------------------------
/// [AI 스마트 검색 헬퍼 (AiSearchHelper)]
/// 사용자의 자연어 질문과 메모리에 로드된 로컬 데이터셋을 조합하여
/// Gemini LLM 모델에 분석을 요청하고, 일치하는 데이터의 ID 목록을 반환받는 전담 클래스입니다.
/// ---------------------------------------------------------------------------
class AiSearchHelper {

  /// ---------------------------------------------------------------------------
  /// [인원 전용 AI 검색]
  /// ---------------------------------------------------------------------------
  static Future<List<String>> searchUsers(String query, List<UserModel> users) async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final String apiKey = (prefs.getString('pref_gemini_api_key') ?? '').trim();

    if (apiKey.isEmpty) {
      throw Exception("환경설정(톱니바퀴) 화면에서 구글 AI(Gemini) API 키를 먼저 등록해주세요.");
    }

    if (users.isEmpty || query.trim().isEmpty) {
      return [];
    }

    final List<Map<String, dynamic>> miniDataset = users.map((UserModel u) {
      return {
        'id': u.id,
        'name': u.name,
        'department': u.department,
        'code': u.code,
        'role': u.role,
        'remarks': u.remarks,
      };
    }).toList();

    final String datasetJson = jsonEncode(miniDataset);

    const String systemPrompt = """
      You are an intelligent database search assistant for a Flutter application.
      You will be provided with a JSON array of user data and a natural language search query in Korean.
      Analyze the data contextually and return ONLY a valid JSON array of string 'id's that match the query.
      Do NOT return any other text, markdown formatting blocks, or explanations. 
      Just output the raw JSON array exactly like this: ["id1", "id2"].
      If no users match the query, return an empty array: [].
      Search intelligently (e.g. synonyms, partial matches, contextual filtering).
    """;

    final String userPrompt = "Dataset: $datasetJson\n\nSearch Query: $query";

    // ignore: spell-check
    final String baseHost = 'https://generativelanguage.googleapis.com';

    final Map<String, dynamic> payload = {
      "contents": [
        {
          "parts": [{"text": userPrompt}]
        }
      ],
      "systemInstruction": {
        "parts": [{"text": systemPrompt}]
      },
      "generationConfig": {
        "responseMimeType": "application/json",
      }
    };

    final List<String> targetModels = [
      'gemini-2.0-flash' // 정답으로 확인된 최신 모델
    ];

    List<String> failedLogs = [];

    for (String modelName in targetModels) {
      // ignore: spell-check
      final String apiPath = '/v1beta/models/$modelName:generateContent';
      final Uri url = Uri.parse('$baseHost$apiPath?key=$apiKey');

      int attempt = 0;
      final List<int> delays = [2, 4, 8];

      while (attempt < 3) {
        try {
          final http.Response response = await http.post(
            url,
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode(payload),
          );

          if (response.statusCode == 200) {
            final Map<String, dynamic> jsonResponse = jsonDecode(response.body);
            String contentText = jsonResponse['candidates']?[0]?['content']?['parts']?[0]?['text'] ?? "[]";

            final String mdCodeBlock = '```${'json'}';
            final String mdTick = '```';

            contentText = contentText.replaceAll(RegExp(mdCodeBlock, caseSensitive: false), '');
            contentText = contentText.replaceAll(mdTick, '').trim();

            try {
              final List<dynamic> idsDynamic = jsonDecode(contentText);
              return idsDynamic.map((dynamic e) => e.toString()).toList();
            } catch (parseError) {
              throw Exception("JSON파싱실패: $parseError\n(수신된 데이터: $contentText)");
            }
          } else if (response.statusCode == 429) {
            // 🔥 [429 에러 정밀 분석기]
            String reason = "일시적 서버 과부하 (잠시 후 시도)";
            try {
              final Map<String, dynamic> errJson = jsonDecode(response.body);
              final String errMsg = errJson['error']?['message'] ?? '';
              // 구글이 일일 할당량(Quota)을 다 썼다고 명시하는 경우
              if (errMsg.toLowerCase().contains('quota')) {
                reason = "무료 할당량(Quota) 소진. 다른 구글 계정으로 새 API키를 발급받아주세요.";
              }
            } catch (_) {}

            failedLogs.add("$modelName(429: $reason)");
            break;
          } else if (response.statusCode == 404) {
            failedLogs.add("$modelName(404 없음)");
            break;
          } else if (response.statusCode == 400) {
            try {
              final Map<String, dynamic> errJson = jsonDecode(response.body);
              final String errMsg = errJson['error']?['message'] ?? 'Bad Request';
              failedLogs.add("$modelName(400: $errMsg)");
            } catch(_) {
              failedLogs.add("$modelName(400 요청오류)");
            }
            break;
          } else if (response.statusCode == 403) {
            failedLogs.add("$modelName(403 권한없음)");
            break;
          } else {
            throw Exception("HTTP ${response.statusCode}");
          }
        } catch (e) {
          if (attempt == 2) {
            String errMsg = e.toString().replaceAll('\n', ' ');
            if (errMsg.length > 30) errMsg = errMsg.substring(0, 30) + '...';
            failedLogs.add("$modelName(오류: $errMsg)");
            break;
          }
          await Future.delayed(Duration(seconds: delays[attempt]));
          attempt++;
        }
      }
    }

    throw Exception("AI 검색 서버와 통신할 수 없습니다.\n(시도 내역: ${failedLogs.join(', ')})");
  }

  /// ---------------------------------------------------------------------------
  /// [물품(자산) 전용 AI 검색]
  /// ---------------------------------------------------------------------------
  static Future<List<String>> searchProducts(String query, List<ProductModel> products) async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final String apiKey = (prefs.getString('pref_gemini_api_key') ?? '').trim();

    if (apiKey.isEmpty) {
      throw Exception("환경설정(톱니바퀴) 화면에서 구글 AI(Gemini) API 키를 먼저 등록해주세요.");
    }

    if (products.isEmpty || query.trim().isEmpty) {
      return [];
    }

    final List<Map<String, dynamic>> miniDataset = products.map((ProductModel p) {
      return {
        'id': p.id,
        'name': p.name,
        'category': p.category,
        'location': p.location,
        'status': p.status,
        'spec': p.spec,
        'quantity': p.quantity,
        'safety_stock': p.safetyStock,
      };
    }).toList();

    final String datasetJson = jsonEncode(miniDataset);

    const String systemPrompt = """
      You are an intelligent database search assistant for a Flutter application handling Inventory/Assets.
      You will be provided with a JSON array of product data and a natural language search query in Korean.
      Analyze the data contextually and return ONLY a valid JSON array of string 'id's that match the query.
      Do NOT return any other text, markdown formatting blocks, or explanations. 
      Just output the raw JSON array exactly like this: ["id1", "id2"].
      If no products match the query, return an empty array: [].
      Search intelligently (e.g. synonyms like '랩탑'='노트북', semantic filtering like '수량이 부족한' = quantity < safety_stock).
    """;

    final String userPrompt = "Dataset: $datasetJson\n\nSearch Query: $query";

    // ignore: spell-check
    final String baseHost = 'https://generativelanguage.googleapis.com';

    final Map<String, dynamic> payload = {
      "contents": [
        {
          "parts": [{"text": userPrompt}]
        }
      ],
      "systemInstruction": {
        "parts": [{"text": systemPrompt}]
      },
      "generationConfig": {
        "responseMimeType": "application/json",
      }
    };

    final List<String> targetModels = [
      'gemini-2.0-flash'
    ];

    List<String> failedLogs = [];

    for (String modelName in targetModels) {
      // ignore: spell-check
      final String apiPath = '/v1beta/models/$modelName:generateContent';
      final Uri url = Uri.parse('$baseHost$apiPath?key=$apiKey');

      int attempt = 0;
      final List<int> delays = [2, 4, 8];

      while (attempt < 3) {
        try {
          final http.Response response = await http.post(
            url,
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode(payload),
          );

          if (response.statusCode == 200) {
            final Map<String, dynamic> jsonResponse = jsonDecode(response.body);
            String contentText = jsonResponse['candidates']?[0]?['content']?['parts']?[0]?['text'] ?? "[]";

            final String mdCodeBlock = '```${'json'}';
            final String mdTick = '```';

            contentText = contentText.replaceAll(RegExp(mdCodeBlock, caseSensitive: false), '');
            contentText = contentText.replaceAll(mdTick, '').trim();

            try {
              final List<dynamic> idsDynamic = jsonDecode(contentText);
              return idsDynamic.map((dynamic e) => e.toString()).toList();
            } catch (parseError) {
              throw Exception("JSON파싱실패: $parseError\n(수신된 데이터: $contentText)");
            }
          } else if (response.statusCode == 429) {
            // 🔥 [429 에러 정밀 분석기]
            String reason = "일시적 서버 과부하 (잠시 후 시도)";
            try {
              final Map<String, dynamic> errJson = jsonDecode(response.body);
              final String errMsg = errJson['error']?['message'] ?? '';
              if (errMsg.toLowerCase().contains('quota')) {
                reason = "무료 할당량(Quota) 소진. 다른 구글 계정으로 새 API키를 발급받아주세요.";
              }
            } catch (_) {}

            failedLogs.add("$modelName(429: $reason)");
            break;
          } else if (response.statusCode == 404) {
            failedLogs.add("$modelName(404 없음)");
            break;
          } else if (response.statusCode == 400) {
            try {
              final Map<String, dynamic> errJson = jsonDecode(response.body);
              final String errMsg = errJson['error']?['message'] ?? 'Bad Request';
              failedLogs.add("$modelName(400: $errMsg)");
            } catch(_) {
              failedLogs.add("$modelName(400 요청오류)");
            }
            break;
          } else if (response.statusCode == 403) {
            failedLogs.add("$modelName(403 권한없음)");
            break;
          } else {
            throw Exception("HTTP ${response.statusCode}");
          }
        } catch (e) {
          if (attempt == 2) {
            String errMsg = e.toString().replaceAll('\n', ' ');
            if (errMsg.length > 30) errMsg = errMsg.substring(0, 30) + '...';
            failedLogs.add("$modelName(오류: $errMsg)");
            break;
          }
          await Future.delayed(Duration(seconds: delays[attempt]));
          attempt++;
        }
      }
    }

    throw Exception("AI 검색 서버와 통신할 수 없습니다.\n(시도 내역: ${failedLogs.join(', ')})");
  }
}