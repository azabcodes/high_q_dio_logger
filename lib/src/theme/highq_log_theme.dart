class HighQTheme {
  final String successColor;
  final String warningColor;
  final String errorColor;
  final String infoColor;

  const HighQTheme({
    this.successColor = '\x1B[32m', // Green
    this.warningColor = '\x1B[33m', // Yellow
    this.errorColor = '\x1B[31m', // Red
    this.infoColor = '\x1B[36m', // Cyan
  });
}
