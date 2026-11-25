/// The visible collection title, including its source library when known.
String collectionTitleWithLibrary(String title, String? libraryTitle) {
  final library = libraryTitle?.trim();
  if (library == null ||
      library.isEmpty ||
      title == library ||
      title.endsWith(' · $library') ||
      title.endsWith(' ($library)') ||
      title.endsWith(' - $library') ||
      title.endsWith(' – $library')) {
    return title;
  }
  return '$title · $library';
}
