import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/user.dart';

class SessionService {
  static const String _keyUser = 'autolog_current_user';
  static const String _keyActiveVehicleId = 'autolog_active_vehicle_id';
  static const String _keyGuestActiveVehicleId =
      'autolog_guest_active_vehicle_id';
  static const String _keySerfixCache = 'serfix_offline_cache';
  static const String _keySerfixMutations = 'serfix_offline_mutations';

  static Future<void> saveSerfixCache(Map<String, dynamic> cache) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keySerfixCache, jsonEncode(cache));
  }

  static Future<Map<String, dynamic>?> getSerfixCache() async {
    final prefs = await SharedPreferences.getInstance();
    final value = prefs.getString(_keySerfixCache);
    if (value == null) return null;
    try {
      return Map<String, dynamic>.from(jsonDecode(value) as Map);
    } catch (_) {
      return null;
    }
  }

  static Future<void> queueSerfixMutation(Map<String, dynamic> mutation) async {
    final prefs = await SharedPreferences.getInstance();
    final value = prefs.getString(_keySerfixMutations);
    final mutations = value == null
        ? <Map<String, dynamic>>[]
        : (jsonDecode(value) as List)
            .whereType<Map>()
            .map(Map<String, dynamic>.from)
            .toList();
    mutations.removeWhere((item) => item['id'] == mutation['id']);
    mutations.add(mutation);
    await prefs.setString(_keySerfixMutations, jsonEncode(mutations));
  }

  static Future<List<Map<String, dynamic>>> getSerfixMutations() async {
    final prefs = await SharedPreferences.getInstance();
    final value = prefs.getString(_keySerfixMutations);
    if (value == null) return [];
    try {
      return (jsonDecode(value) as List)
          .whereType<Map>()
          .map(Map<String, dynamic>.from)
          .toList();
    } catch (_) {
      return [];
    }
  }

  static Future<void> clearSerfixMutations() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keySerfixMutations);
  }

  static Future<void> saveUser(User user) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyUser, jsonEncode(user.toJson()));
  }

  static Future<User?> getUser() async {
    final prefs = await SharedPreferences.getInstance();
    final str = prefs.getString(_keyUser);
    if (str == null) return null;
    try {
      return User.fromJson(jsonDecode(str));
    } catch (_) {
      return null;
    }
  }

  static Future<void> clearUser() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyUser);
    await prefs.remove(_keyActiveVehicleId);
    await prefs.remove(_keyGuestActiveVehicleId);
  }

  static Future<bool> isGuest() async => (await getUser())?.isGuest ?? false;

  static Future<void> saveActiveVehicleId(int vehicleId,
      {bool guest = false}) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(
        guest ? _keyGuestActiveVehicleId : _keyActiveVehicleId, vehicleId);
  }

  static Future<void> clearActiveVehicleId({bool guest = false}) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(guest ? _keyGuestActiveVehicleId : _keyActiveVehicleId);
  }

  static Future<int?> getActiveVehicleId({bool guest = false}) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(guest ? _keyGuestActiveVehicleId : _keyActiveVehicleId);
  }
}
