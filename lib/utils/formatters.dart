import 'package:intl/intl.dart';

class Formatters {
  static final _time = DateFormat('h:mm:ss a');
  static final _shortTime = DateFormat('h:mm a');
  static final _date = DateFormat('EEEE, MMMM d, y');
  static final _shortDate = DateFormat('MMM d, y');

  static String time(DateTime dt) => _time.format(dt);
  static String shortTime(DateTime dt) => _shortTime.format(dt);
  static String date(DateTime dt) => _date.format(dt);
  static String shortDate(DateTime dt) => _shortDate.format(dt);
}
