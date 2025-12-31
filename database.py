import sqlite3
import json
from typing import Optional, List, Union
from datetime import datetime
from configs import Article

DB_PATH = "./db/advNewsFeed.db"

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
            created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
            followed_journals TEXT
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

    # 创建关键索引
    cursor.execute('CREATE INDEX IF NOT EXISTS idx_articles_doi ON articles(doi)')
    cursor.execute('CREATE INDEX IF NOT EXISTS idx_articles_link ON articles(link)')
    cursor.execute('CREATE INDEX IF NOT EXISTS idx_articles_status ON articles(status)')
    cursor.execute('CREATE INDEX IF NOT EXISTS idx_articles_date ON articles(date)')
    cursor.execute('CREATE INDEX IF NOT EXISTS idx_journals_name ON journals(name)')

    # 提交并关闭
    conn.commit()
    conn.close()


def article_filter(articles: List[dict], db_path: str = DB_PATH) -> List[dict]:

    if not articles:
        return []

    conn = sqlite3.connect(db_path)
    cursor = conn.cursor()

    titles = [a.get('title') for a in articles if a.get('title')]
    links = [a.get('link') for a in articles if a.get('link')]
    dois = [a.get('doi') for a in articles if a.get('doi')]

    existing_titles = set()
    existing_links = set()
    existing_dois = set()

    if titles:
        # 处理 title 中的特殊字符或空值已经在列表生成式中过滤
        placeholders = ','.join(['?'] * len(titles))
        try:
            cursor.execute(f"SELECT title FROM articles WHERE title IN ({placeholders})", titles)
            existing_titles = {row[0] for row in cursor.fetchall()}
        except sqlite3.OperationalError as e:
            print(f"Error querying titles: {e}")

    if links:
        placeholders = ','.join(['?'] * len(links))
        try:
            cursor.execute(f"SELECT link FROM articles WHERE link IN ({placeholders})", links)
            existing_links = {row[0] for row in cursor.fetchall()}
        except sqlite3.OperationalError as e:
            print(f"Error querying links: {e}")

    if dois:
        placeholders = ','.join(['?'] * len(dois))
        try:
            cursor.execute(f"SELECT doi FROM articles WHERE doi IN ({placeholders})", dois)
            existing_dois = {row[0] for row in cursor.fetchall()}
        except sqlite3.OperationalError as e:
            print(f"Error querying dois: {e}")

    conn.close()

    # 3. 过滤文章
    new_articles = []
    for article in articles:
        title = article.get('title')
        link = article.get('link')
        doi = article.get('doi')

        # 如果标题或链接已存在，则跳过
        if (doi and doi in existing_dois) or (title and title in existing_titles) or (link and link in existing_links):
            continue
        
        new_articles.append(article)

    return new_articles


def insert_articles(articles: Union[List[dict], str], db_path: str = DB_PATH):
    if not articles:
        return

    if isinstance(articles, str):
        try:
            articles = json.loads(articles)
        except json.JSONDecodeError as e:
            print(f"Error decoding JSON in insert_articles: {e}")
            return

    conn = sqlite3.connect(db_path)
    cursor = conn.cursor()

    # 准备插入的数据
    data_to_insert = []
    for article in articles:
        # 序列化 authors 列表为 JSON 字符串
        authors_json = json.dumps(article.get('authors', []), ensure_ascii=False)
        
        data_to_insert.append((
            article.get('title'),
            article.get('link'),
            article.get('doi'),
            article.get('date'),
            article.get('journal'),
            authors_json,
            article.get('editor_summary'),
            article.get('structured_abstract'),
            article.get('abstract'),
            article.get('graphical_abstract'),
            article.get('status', 'pending')
        ))

    # 批量插入
    try:
        # 使用 INSERT OR IGNORE 忽略重复项，避免因 DOI/Link 重复报错
        cursor.executemany('''
            INSERT OR IGNORE INTO articles (
                title, link, doi, date, journal_name, authors, 
                editor_summary, structured_abstract, abstract, graphical_abstract, status
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        ''', data_to_insert)
        conn.commit()
        print(f"Successfully inserted {cursor.rowcount} articles.")
    except sqlite3.Error as e:
        print(f"Error inserting articles: {e}")
    finally:
        conn.close()

