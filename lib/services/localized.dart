import 'app_store.dart';

String tr(String ar, String en) => AppStore.instance.isArabic ? ar : en;
