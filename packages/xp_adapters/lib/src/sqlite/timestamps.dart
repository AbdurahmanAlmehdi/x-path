/// How the database stores a point in time: whole microseconds since the Unix
/// epoch, UTC. Integers sort and compare as numbers, which ISO strings with
/// a varying number of fraction digits do not.
int toDatabaseTime(DateTime time) => time.microsecondsSinceEpoch;

/// The point in time stored as [microseconds], in UTC.
DateTime fromDatabaseTime(int microseconds) =>
    DateTime.fromMicrosecondsSinceEpoch(microseconds, isUtc: true);
