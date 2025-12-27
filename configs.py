from typing import TypedDict, Optional

class Article(TypedDict):
    title: Optional[str]
    link: Optional[str]
    doi: Optional[str]
    date: Optional[str]
    journal: Optional[str]
    authors: list[str]
    editor_summary: Optional[str]
    structured_abstract: Optional[str]
    abstract: Optional[str]
    graphical_abstract: Optional[str]
    status: str  
