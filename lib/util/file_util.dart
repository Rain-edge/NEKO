String fileExtension(String path) {
  final idx = path.lastIndexOf('.');
  if (idx < 0) return '';
  return path.substring(idx).toLowerCase();
}

bool isImageFile(String path) {
  final ext = fileExtension(path);
  return ['.jpg', '.jpeg', '.png', '.webp', '.gif', '.bmp'].contains(ext);
}
