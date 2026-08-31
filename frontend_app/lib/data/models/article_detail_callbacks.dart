class ArticleDetailCallbacks {
  final void Function(int articleId)? onArticleRead;
  final void Function(int articleId, bool isFavorite)? onFavoriteChanged;

  const ArticleDetailCallbacks({this.onArticleRead, this.onFavoriteChanged});
}
