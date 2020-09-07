CREATE KEYSPACE IF NOT EXISTS datomic WITH replication = {'class': 'SimpleStrategy', 'replication_factor': 3};
CREATE TABLE IF NOT EXISTS datomic.datomic
(
    id  text PRIMARY KEY,
    rev bigint,
    map text,
    val blob
) WITH gc_grace_seconds = 259200;

