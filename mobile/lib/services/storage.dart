import 'dart:convert'; import 'package:shared_preferences/shared_preferences.dart'; import '../models/contact.dart'; import '../models/emergency.dart';
class Storage { Storage(this._prefs); final SharedPreferences _prefs; static Future<Storage> create() async=>Storage(await SharedPreferences.getInstance());
 List<EmergencyContact> contacts()=>((_prefs.getStringList('contacts')??[]).map((s)=>EmergencyContact.fromJson((jsonDecode(s)as Map).cast<String,dynamic>())).toList()..sort((a,b)=>a.priority.compareTo(b.priority)));
 Future<void> saveContacts(List<EmergencyContact> v)=>_prefs.setStringList('contacts',v.map((c)=>jsonEncode(c.toJson())).toList());
 List<EventRecord> history()=>((_prefs.getStringList('history')??[]).map((s)=>EventRecord.fromJson((jsonDecode(s)as Map).cast<String,dynamic>())).toList());
 Future<void> addEvent(EventRecord r) async { final items=history()..insert(0,r); await _prefs.setStringList('history',items.take(100).map((e)=>jsonEncode(e.toJson())).toList()); }
 bool get onboarded=>_prefs.getBool('onboarded')??false; Future<void> finishOnboarding()=>_prefs.setBool('onboarded',true);
}
