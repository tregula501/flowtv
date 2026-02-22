/// String extension methods
extension StringExtensions on String {
  /// Capitalize first letter
  String get capitalize {
    if (isEmpty) return this;
    return '${this[0].toUpperCase()}${substring(1)}';
  }

  /// Capitalize each word
  String get titleCase {
    if (isEmpty) return this;
    return split(' ').map((word) => word.capitalize).join(' ');
  }

  /// Check if string is a valid HTTP/HTTPS URL
  bool get isValidUrl {
    final uri = Uri.tryParse(this);
    return uri != null &&
        uri.hasScheme &&
        (uri.scheme == 'http' || uri.scheme == 'https') &&
        uri.host.isNotEmpty;
  }

  /// Check if string is a valid M3U URL
  bool get isM3uUrl {
    return isValidUrl && (endsWith('.m3u') || endsWith('.m3u8') || contains('get.php'));
  }

  /// Extract file extension
  String? get fileExtension {
    final dotIndex = lastIndexOf('.');
    if (dotIndex == -1 || dotIndex == length - 1) return null;
    return substring(dotIndex + 1).toLowerCase();
  }

  /// Truncate string with ellipsis
  String truncate(int maxLength) {
    if (length <= maxLength) return this;
    return '${substring(0, maxLength - 3)}...';
  }
}
