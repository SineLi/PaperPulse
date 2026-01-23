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
