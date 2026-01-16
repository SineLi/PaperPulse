import logging
from db.database import get_db_connection

from utils.fetcher.AAAS_fetcher import ScienceFetcher
from utils.fetcher.ACS_fetcher import ACSFetcher
from utils.fetcher.Cell_fetcher import CellFetcher
from utils.fetcher.Elsevier_fetcher import ElsevierFetcher
from utils.fetcher.Frontiers_fetcher import FrontiersFetcher
from utils.fetcher.MDPI_fetcher import MDPIFetcher
from utils.fetcher.Nat_fetcher import NatureFetcher
from utils.fetcher.RSC_fetcher import RSCFetcher
from utils.fetcher.Taylor_fetcher import TaylorFetcher
from utils.fetcher.Wiely_fetcher import WileyFetcher

# 日志配置
logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(name)s - %(levelname)s - %(message)s')
logger = logging.getLogger("MainFetcher")

# 出版商与抓取器类的映射关系
PUBLISHER_FETCHER_MAP = {
    "Springer Nature": NatureFetcher,
    "Cell Press": CellFetcher,
    "Elsevier": ElsevierFetcher,
    "Science": ScienceFetcher,
    "AAAS": ScienceFetcher,
    "American Chemical Society": ACSFetcher,
    "Royal Society of Chemistry": RSCFetcher,
    "Wiley": WileyFetcher,
    "Taylor & Francis": TaylorFetcher,
    "MDPI": MDPIFetcher,
    "Frontiers": FrontiersFetcher
}

def run_enabled_fetchers():
    logger.info("Starting run_enabled_fetchers...")
    
    with get_db_connection() as conn:
        cursor = conn.cursor()
        # 获取所有启用了抓取的期刊
        cursor.execute("""
            SELECT id, name, publisher, rss_url, official_url 
            FROM journals 
            WHERE crawler_enabled = 1
        """)
        active_journals = cursor.fetchall()

    if not active_journals:
        logger.info("No active journals found with crawler_enabled=1.")
        return

    for journal in active_journals:
        # 使用字典访问（因为使用了 Row factory）
        j_id = journal['id']
        j_name = journal['name']
        j_publisher = journal['publisher']
        # 优先使用 RSS URL，备选官网 URL
        j_url = journal['rss_url'] if journal['rss_url'] else journal['official_url']

        if not j_url:
            logger.warning(f"No URL found for {j_name}. Skipping.")
            continue

        logger.info(f"Processing journal: {j_name} (Publisher: {j_publisher})")

        # 查找匹配的抓取器类
        fetcher_class = PUBLISHER_FETCHER_MAP.get(j_publisher)

        try:
            # 实例化抓取器 (已将所有 fetcher 更新为支持 url 和 name 参数)
            fetcher = fetcher_class(url=j_url, name=j_name, max_workers=5, journal_id=j_id)
            
            logger.info(f"Running {fetcher.__class__.__name__} for {j_name}...")
            fetcher.run()
            
        except Exception as e:
            logger.error(f"Error running fetcher for {j_name}: {e}")

if __name__ == "__main__":
    run_enabled_fetchers()

    def run_all_fetchers(self):
        for fetcher in self.fetchers:
            logger.info(f"Running fetcher: {fetcher.__class__.__name__}")
            new_articles = fetcher.fetch_new_articles()
            logger.info(f"Fetched {len(new_articles)} new articles from {fetcher.__class__.__name__}")
            for article in new_articles:
                self.article_repo.insert_article(article)
        logger.info("All fetchers completed.")