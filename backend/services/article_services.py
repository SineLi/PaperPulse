import sqlite3
import logging
from db.database import get_db_connection
from typing import Optional, List, Union, TypedDict
import json

logger = logging.getLogger(__name__)

class Article(TypedDict):
    title: str
    link: str
    doi: Optional[str]
    date: Optional[str]
    journal: Optional[str]
    authors: list[str]
    editor_summary: Optional[str]
    structured_abstract: Optional[str]
    abstract: Optional[str]
    graphical_abstract: Optional[str]
    status: str  

class ArticleService:
    def article_filter(self,articles: List[dict]) -> List[dict]:

        if not articles:
            return []

        titles = [a.get('title') for a in articles if a.get('title')]
        links = [a.get('link') for a in articles if a.get('link')]
        dois = [a.get('doi') for a in articles if a.get('doi')]

        existing_titles = set()
        existing_links = set()
        existing_dois = set()

        with get_db_connection() as conn:
            cursor = conn.cursor()

            if titles:
                # 处理 title 中的特殊字符或空值已经在列表生成式中过滤
                placeholders = ','.join(['?'] * len(titles))
                try:
                    cursor.execute(f"SELECT title FROM articles WHERE title IN ({placeholders})", titles)
                    existing_titles.update(row[0] for row in cursor.fetchall())
                    cursor.execute(f"SELECT title FROM non_article_entries WHERE title IN ({placeholders})", titles)
                    existing_titles.update(row[0] for row in cursor.fetchall())
                except sqlite3.OperationalError as e:
                    logger.error(f"Error querying titles: {e}")

            if links:
                placeholders = ','.join(['?'] * len(links))
                try:
                    cursor.execute(f"SELECT link FROM articles WHERE link IN ({placeholders})", links)
                    existing_links.update(row[0] for row in cursor.fetchall())
                    cursor.execute(f"SELECT link FROM non_article_entries WHERE link IN ({placeholders})", links)
                    existing_links.update(row[0] for row in cursor.fetchall())
                except sqlite3.OperationalError as e:
                    logger.error(f"Error querying links: {e}")

            if dois:
                placeholders = ','.join(['?'] * len(dois))
                try:
                    cursor.execute(f"SELECT doi FROM articles WHERE doi IN ({placeholders})", dois)
                    existing_dois.update(row[0] for row in cursor.fetchall())
                    cursor.execute(f"SELECT doi FROM non_article_entries WHERE doi IN ({placeholders})", dois)
                    existing_dois.update(row[0] for row in cursor.fetchall())
                except sqlite3.OperationalError as e:
                    logger.error(f"Error querying dois: {e}")
                

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


    def insert_articles(self, articles: Union[List[dict], str]):
        if not articles:
            return

        if isinstance(articles, str):
            try:
                articles = json.loads(articles)
            except json.JSONDecodeError as e:
                logger.error(f"Error decoding JSON in insert_articles: {e}")
                return

        with get_db_connection() as conn:
            cursor = conn.cursor()
            
            journal_names = list({article.get('journal') for article in articles if article.get('journal')})
            journal_map = {}
            if journal_names:
                placeholders = ','.join(['?'] * len(journal_names))
                try:
                    cursor.execute(f"SELECT name, id FROM journals WHERE name IN ({placeholders})", journal_names)
                    journal_map = {row[0]: row[1] for row in cursor.fetchall()}
                except sqlite3.Error as e:
                    logger.error(f"Error querying journal IDs: {e}")

            # 准备插入的数据
            data_to_insert = []
            no_article_entries = []
            for article in articles:
                if not article.get('title') or not article.get('link') or not article.get('abstract'):
                    journal_name = article.get('journal')
                    journal_id = journal_map.get(journal_name)
                    no_article_entries.append({
                        'title': article.get('title'),
                        'link': article.get('link'),
                        'date': article.get('date'),
                        'journal_id': journal_id,
                        'doi': article.get('doi')
                    })
                    continue
                # 序列化 authors 列表为 JSON 字符串
                authors_json = json.dumps(article.get('authors', []), ensure_ascii=False)
                
                journal_name = article.get('journal')
                journal_id = journal_map.get(journal_name)

                data_to_insert.append((
                    article.get('title'),
                    article.get('link'),
                    article.get('doi'),
                    article.get('date'),
                    journal_id,
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
                        title, link, doi, date, journal_id, authors, 
                        editor_summary, structured_abstract, abstract, graphical_abstract, status
                    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                ''', data_to_insert)
                conn.commit()
                logger.info(f"Successfully inserted {cursor.rowcount} articles.")
            except sqlite3.Error as e:
                logger.error(f"Error inserting articles: {e}")
            finally:
                pass

            try:
                for entry in no_article_entries:
                    self.insert_non_article_entry(entry)
            except Exception as e:
                logger.error(f"Error inserting non-article entries: {e}")

    
    def insert_non_article_entry(self, entry: dict):
        if not entry.get('title') or not entry.get('link'):
            logger.warning("Non-article entry must have at least a title and a link.")
            return

        with get_db_connection() as conn:
            cursor = conn.cursor()
            try:
                cursor.execute('''
                    INSERT OR IGNORE INTO non_article_entries (
                        title, link, date, journal_id, doi
                    ) VALUES (?, ?, ?, ?, ?)
                ''', (
                    entry.get('title'),
                    entry.get('link'),
                    entry.get('date'),
                    entry.get('journal_id'),
                    entry.get('doi')
                ))
                conn.commit()
                if cursor.rowcount == 1:
                    logger.info("Inserted non-article entry: %s", entry.get("title"))
                else:
                    logger.info("Skipped non-article entry (duplicate/constraint): %s", entry.get("title"))
            except sqlite3.Error as e:
                logger.error(f"Error inserting non-article entry: {e}")
            finally:
                pass