import 'entities.dart';

List<String> _comicSealCategories = const <String>[];
List<String> _comicSealTitleWords = const <String>[];

List<String> currentComicSealCategories() => _comicSealCategories;

List<String> currentComicSealTitleWords() => _comicSealTitleWords;

void updateComicSealRules({
  List<String>? categories,
  List<String>? titleWords,
}) {
  if (categories != null) {
    _comicSealCategories = categories;
  }
  if (titleWords != null) {
    _comicSealTitleWords = titleWords;
  }
}

bool matchComicSealedByRules(ComicSimple comic) {
  final categoryTitles = <String>[];
  if (comic.category?.title != null && comic.category!.title!.isNotEmpty) {
    categoryTitles.add(comic.category!.title!);
  }
  if (comic.categorySub?.title != null &&
      comic.categorySub!.title!.isNotEmpty) {
    categoryTitles.add(comic.categorySub!.title!);
  }
  for (final value in categoryTitles) {
    if (_comicSealCategories.contains(value)) {
      return true;
    }
  }
  for (final word in _comicSealTitleWords) {
    if (word.isNotEmpty && comic.name.contains(word)) {
      return true;
    }
  }
  return false;
}
