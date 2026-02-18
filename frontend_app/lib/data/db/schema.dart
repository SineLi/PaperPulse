const String createArticlesTable = '''
   CREATE TABLE articles (
     article_id INTEGER PRIMARY KEY,
     title TEXT NOT NULL,
     abs TEXT NOT NULL,
     summary TEXT NOT NULL,
     graphical_abstract_url TEXT,
     graphical_abstract_cache_path TEXT,
     published_date TEXT NOT NULL,
     authors TEXT,
     journal_id INTEGER NOT NULL,
     journal_name TEXT NOT NULL,
     journal_abbreviation TEXT NOT NULL,
     doi TEXT NOT NULL,
     is_favorite INTEGER NOT NULL DEFAULT 0,
     is_read INTEGER NOT NULL DEFAULT 0
   );
 ''';

const String createJournalsTable = '''
   CREATE TABLE journals (
     journal_id INTEGER PRIMARY KEY,
     name TEXT NOT NULL,
     abbreviation TEXT NOT NULL,
     if0 REAL,
     if5 REAL,
     sci INTEGER DEFAULT 0,
     CASUp TEXT, 
     CASBase TEXT, 
     publisher TEXT,
     update_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
   );
 ''';
const String createUserSubscriptionsTable = '''
   CREATE TABLE user_subscriptions (
     journal_id INTEGER NOT NULL PRIMARY KEY,
     subscribed_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
   );
 ''';

const String createSyncQueueTable = '''
   CREATE TABLE sync_queue (
     id INTEGER PRIMARY KEY AUTOINCREMENT,
     article_id INTEGER NOT NULL,
     action TEXT NOT NULL,
     timestamp INTEGER NOT NULL
   );
 ''';

const String createMetadataTable = '''
   CREATE TABLE metadata (
     key TEXT PRIMARY KEY,
     value TEXT NOT NULL
   );
 ''';
