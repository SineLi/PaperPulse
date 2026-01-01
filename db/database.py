import sqlite3
from contextlib import contextmanager
import os
from pathlib import Path

DB_PATH = str(Path(__file__).resolve().parents[1] / "db/advNewsFeed.db")

def init_database(db_path: str = DB_PATH):
    """初始化数据库并创建三张表"""
    conn = sqlite3.connect(db_path)
    cursor = conn.cursor()

    # 1. 用户表 (users)
    cursor.execute('''
        CREATE TABLE IF NOT EXISTS users (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            username TEXT UNIQUE NOT NULL,
            email TEXT UNIQUE NOT NULL,
            password_hash TEXT NOT NULL,
            created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
        )
    '''
)
    # 2. 期刊表 (journals)
    cursor.execute('''
        CREATE TABLE IF NOT EXISTS journals (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            name TEXT UNIQUE NOT NULL,      -- 期刊全称 (e.g., "Nature")
            abbreviation TEXT,              -- 期刊简称 (e.g., "Nat.")
            if REAL,                      -- 影响因子 (e.g., 42.778)
            if5 REAL,                      -- 5年影响因子
            sci INTEGER DEFAULT 0,          -- SCI分区 (1/2/3/4, 0=None)
            CASUp TEXT,                     -- 中科院升级版分区
            CASBase TEXT,                   -- 中科院基础版分区
            publisher TEXT,                 -- 出版商 (e.g., "Springer Nature")
            issn TEXT,                      -- ISSN (e.g., "0028-0836")
            eissn TEXT,                     -- eISSN (在线 ISSN)
            official_url TEXT,              -- 期刊官网 (e.g., "https://www.nature.com/nature")
            rss_url TEXT,                   -- RSS 源 (e.g., "https://www.nature.com/nature.rss")
            crawler_enabled BOOLEAN DEFAULT 0, -- 是否启用爬虫 (0/1)
            created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
        )
    ''')

    # 3. 文献表 (articles)
    cursor.execute('''
        CREATE TABLE IF NOT EXISTS articles (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            title TEXT NOT NULL,
            link TEXT UNIQUE NOT NULL,      -- 原文链接 (DOI URL 或期刊页面)
            doi TEXT UNIQUE,                -- DOI (e.g., "10.1038/s41586-023-06204-5")
            date TEXT,                      -- 发表日期 (ISO 8601: "2023-12-24")
            journal_name TEXT,              -- 期刊名称 (冗余字段，关联 journals.name)
            authors TEXT,                   -- JSON 格式: ["Zhang, Y.", "Li, X."]
            editor_summary TEXT,            -- 编辑摘要
            structured_abstract TEXT,        -- 结构化摘要 (JSON 或 XML)
            abstract TEXT,                  -- 普通摘要
            graphical_abstract TEXT,         -- 图形摘要 (URL 或 Base64 编码)
            status TEXT NOT NULL DEFAULT 'pending', -- 状态: pending/processed/failed/skipped
            created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
            processed_at TIMESTAMP,         -- LLM 处理完成时间
            -- 外键约束 (SQLite 默认不强制，但建议逻辑关联)
            FOREIGN KEY (journal_name) REFERENCES journals(name)
        )
    ''')

    # 4. 用户关注期刊关联表 (user_journal_subscriptions)
    cursor.execute('''
        CREATE TABLE IF NOT EXISTS user_journal_subscriptions (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            user_id INTEGER NOT NULL,
            journal_id INTEGER NOT NULL,
            created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
            UNIQUE(user_id, journal_id), -- 防止重复关注
            FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE,
            FOREIGN KEY (journal_id) REFERENCES journals(id) ON DELETE CASCADE
        )
    ''')

    # 5. 用户文章阅读状态表 (user_article_reads)
    cursor.execute('''
        CREATE TABLE IF NOT EXISTS user_article_reads (
            user_id INTEGER NOT NULL,
            article_id INTEGER NOT NULL,
            read_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
            PRIMARY KEY (user_id, article_id),
            FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE,
            FOREIGN KEY (article_id) REFERENCES articles(id) ON DELETE CASCADE
        )
    ''')

    # 创建关键索引
    cursor.execute('CREATE INDEX IF NOT EXISTS idx_articles_doi ON articles(doi)')
    cursor.execute('CREATE INDEX IF NOT EXISTS idx_articles_link ON articles(link)')
    cursor.execute('CREATE INDEX IF NOT EXISTS idx_articles_status ON articles(status)')
    cursor.execute('CREATE INDEX IF NOT EXISTS idx_articles_date ON articles(date)')
    cursor.execute('CREATE INDEX IF NOT EXISTS idx_journals_name ON journals(name)')
    cursor.execute('CREATE INDEX IF NOT EXISTS idx_uar_user ON user_article_reads(user_id)')

    # 提交并关闭
    conn.commit()
    conn.close()

@contextmanager
def get_db_connection():
    try:
        conn = sqlite3.connect(DB_PATH)
        conn.row_factory = sqlite3.Row
    except sqlite3.Error as e:
        print(f"Error connecting to database: {e}")
        raise
    try:
        yield conn
    except Exception:
        conn.rollback()
        raise
    else:
        conn.commit()
    finally:
        conn.close()