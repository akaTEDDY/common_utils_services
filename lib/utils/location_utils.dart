import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/services.dart';
import 'package:hive/hive.dart';
import 'package:common_utils_services/models/location_history.dart';
import 'package:common_utils_services/models/location.dart';
import 'package:common_utils_services/services/ai_services.dart';
import 'package:common_utils_services/services/notification_service.dart';

// 위치 데이터 콜백 타입 정의
typedef PlengiListener = void Function(dynamic location);

class LocationUtils {
  static const platform = MethodChannel('plengi.ai/fromFlutter');
  static const int maxLocationHistory = 10;
  // 위도 1도당 거리 (약 111km)
  static const double latDegreeToMeters = 111000.0;
  // 경도 1도당 거리 (위도에 따라 변하지만, 한국 기준으로 약 88.8km)
  static const double lonDegreeToMeters = 88800.0;

  // 현재 위치 관련 키워드
  static const List<String> _currentLocationKeywords = [
    '현재 위치',
    '지금 위치',
    '여기',
    '이곳',
    '이 위치',
    '현재',
    '지금',
    '내 위치',
    '나의 위치',
    '우리 위치',
    '이 주변',
    '주변',
    '이 근처',
    '근처',
    '이 동네',
    '이 지역',
    '이 곳',
    '이 장소',
    '이 주소',
    '이 좌표',
  ];

  // 과거 위치 관련 키워드
  static const List<String> _pastLocationKeywords = [
    '갔던',
    '갔었던',
    '있었던',
    '방문했던',
    '방문했었던',
    '다녀온',
    '다녀왔던',
    '다녀왔었던',
    '가봤던',
    '가봤었던',
    '방문한',
    '방문했던',
    '방문했었던',
    '이전에',
    '전에',
    '히스토리',
  ];

  // 현재 위치 관련 질문인지 확인
  static bool isCurrentLocationQuestion(String message) {
    return _currentLocationKeywords.any((keyword) => message.contains(keyword));
  }

  // 과거 위치 관련 질문인지 확인
  static bool isPastLocationQuestion(String message) {
    return _pastLocationKeywords.any((keyword) => message.contains(keyword));
  }

  // 위치 정보가 필요한 요청인지 확인
  static bool needsLocation(String message) {
    return isCurrentLocationQuestion(message) ||
        isPastLocationQuestion(message);
  }

  // 위치 정보 컨텍스트 생성
  static String getLocationContext(
    String message,
    List<LocationHistory> locationHistory,
  ) {
    if (locationHistory.isEmpty) return '';

    final context = StringBuffer();

    if (isPastLocationQuestion(message)) {
      // 과거 위치 관련 질문인 경우
      context.writeln('최근 방문 기록:');
      for (var i = locationHistory.length - 1; i >= 0; i--) {
        final location = locationHistory[i];
        context.writeln(
          '- ${location.displayName} (${location.formattedTime})',
        );
      }
    } else if (isCurrentLocationQuestion(message)) {
      // 현재 위치 관련 질문인 경우
      final latestLocation = locationHistory.first;
      context.writeln(
        '현재 위치는 ${latestLocation.displayName} (${latestLocation.formattedTime})',
      );
    }

    return context.toString();
  }

  // 두 지점 간의 거리를 계산하는 함수
  static double calculateDistance(
    Map<String, dynamic> currentLocation,
    Map<String, dynamic> lastLocation,
  ) {
    final double? newLat = currentLocation['lat']?.toDouble();
    final double? newLng = currentLocation['lng']?.toDouble();
    if (newLat != null && newLng != null) {
      final double? lastLat = lastLocation['lat']?.toDouble();
      final double? lastLng = lastLocation['lng']?.toDouble();
      if (lastLat != null && lastLng != null) {
        final double latDiff = (newLat - lastLat).abs();
        final double lngDiff = (newLng - lastLng).abs();

        // 피타고라스 정리로 대략적인 거리 계산
        final double latMeters = latDiff * latDegreeToMeters;
        final double lngMeters = lngDiff * lonDegreeToMeters;

        return sqrt(latMeters * latMeters + lngMeters * lngMeters);
      }
    }
    return -1;
  }

  static double toRadians(double degree) {
    return degree * pi / 180;
  }

  // 현재 위치 가져오기
  static Future<String?> getCurrentLocation() async {
    try {
      final String? location = await platform.invokeMethod('searchPlace');
      return location;
    } on PlatformException catch (e) {
      print('위치 정보 가져오기 실패: ${e.message}');
      return null;
    }
  }

  static bool isLocationSignificant(
    Map<String, dynamic> currentLocation,
    Map<String, dynamic> lastLocation,
  ) {
    if (lastLocation.isEmpty) {
      return false;
    }

    // loplat_id가 있는 경우
    final String? newLoplatId = currentLocation['place']?['loplat_id']
        ?.toString();
    if (newLoplatId != null) {
      final String? lastLoplatId = lastLocation['place']?['loplat_id']
          ?.toString();
      if (lastLoplatId != newLoplatId) {
        return true;
      }
    }

    // 둘 중 하나라도 loplat_id가 없는 경우 위도/경도로 거리 계산
    final double? newLat = currentLocation['lat']?.toDouble();
    final double? newLng = currentLocation['lng']?.toDouble();
    if (newLat != null && newLng != null) {
      final double? lastLat = lastLocation['lat']?.toDouble();
      final double? lastLng = lastLocation['lng']?.toDouble();

      if (lastLat != null && lastLng != null) {
        final double distance = calculateDistance(
          currentLocation,
          lastLocation,
        );
        if (distance < 100) {
          return true; // 100m 미만이면 추가하지 않음
        }
      }
    }

    return false;
  }
}

// 위치 히스토리 관리 클래스
class LocationHistoryManager {
  late Box<LocationHistory> locationHistoryBox;
  late StreamSubscription? _subscription;
  PlengiListener? _listener;

  Future<void> initialize(PlengiListener? plengiListener) async {
    try {
      // 이벤트 스트림 구독
      Stream<dynamic> stream = EventChannel(
        'plengi.ai/toFlutter',
      ).receiveBroadcastStream();

      _subscription = stream.listen(
        (dynamic location) {
          if (_listener != null) {
            _listener!(location);
          }
        },
        onError: (dynamic error) {
          print('Flutter: Error on EventChannel: $error');
        },
        onDone: () {
          print('Flutter: EventChannel stream done.');
        },
        cancelOnError: true,
      );

      locationHistoryBox = await Hive.openBox<LocationHistory>(
        'locationHistory',
      );
    } catch (e) {
      print('위치 매니저 초기화 실패: $e');
    }
  }

  String _summarizePlengiResponse(String response) {
    return response.split('\n')[0];
  }

  List<LocationHistory> get locationHistory =>
      locationHistoryBox.values.toList();

  void checkLocationNeedsInteraction(String location) {
    try {
      final Map<String, dynamic> locationData = json.decode(location);
      final loc = Location.fromJson(locationData);
      print("locationData $loc");
    } catch (e) {
      print('location interaction 실패: $e');
    }
  }

  void addLocationHistory(String location) {
    try {
      final Map<String, dynamic> locationData = json.decode(location);

      // 히스토리가 있는데 위치의 유의미한 변화가 없으면 add 하지 않음
      final List<LocationHistory> currentHistory = locationHistoryBox.values
          .toList();
      if (currentHistory.isNotEmpty) {
        if (!LocationUtils.isLocationSignificant(
          locationData,
          currentHistory.first.toJson(),
        )) {
          return;
        }
      }

      final locationHistory = LocationHistory.fromJson(locationData);
      locationHistoryBox.add(locationHistory);

      // 크기 제한 초과 시 오래된 데이터 제거
      while (locationHistoryBox.length > LocationUtils.maxLocationHistory) {
        final oldestKey = locationHistoryBox.keyAt(0);
        locationHistoryBox.delete(oldestKey);
      }
    } catch (e) {
      print('위치 히스토리 추가 실패: $e');
    }
  }

  void clear() {
    locationHistoryBox.clear();
  }

  void dispose() {
    _subscription?.cancel();
  }
}
