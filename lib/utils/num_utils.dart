/// Safely parse a value from a Laravel API response into a double.
///
/// Laravel's `decimal:N` Eloquent casts (used for money fields like
/// `fare`, `balance`, `amount`) serialize to JSON STRINGS (e.g. "150.00"),
/// not JSON numbers. A plain `as num?` cast throws
/// "type 'String' is not a subtype of type 'num?'" on those fields.
///
/// This accepts num, String, or null and never throws.
double parseApiDouble(dynamic value, {double fallback = 0}) {
  if (value == null) return fallback;
  if (value is num) return value.toDouble();
  if (value is String) return double.tryParse(value) ?? fallback;
  return fallback;
}

/// Same idea for integers.
int parseApiInt(dynamic value, {int fallback = 0}) {
  if (value == null) return fallback;
  if (value is int) return value;
  if (value is num) return value.toInt();
  if (value is String) return int.tryParse(value) ?? double.tryParse(value)?.toInt() ?? fallback;
  return fallback;
}
