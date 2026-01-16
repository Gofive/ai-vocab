import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';

class AppTheme {
  // 主色调
  static const Color primaryColor = Colors.indigo;

  // 语义色
  static const Color successColor = Color(0xFF10B981);
  static const Color warningColor = Color(0xFFF59E0B);
  static const Color errorColor = Color(0xFFEF4444);
  static const Color infoColor = Color(0xFF3B82F6);

  // 亮色主题颜色
  static const Color lightBackground = Color(0xFFF8FAFC);
  static const Color lightSurface = Colors.white;
  static const Color lightTextPrimary = Color(0xFF1E293B);
  static const Color lightTextSecondary = Color(0xFF64748B);
  static const Color lightTextTertiary = Color(0xFF94A3B8);
  static const Color lightDivider = Color(0xFFE2E8F0);
  static const Color lightBorder = Color(0xFFCBD5E1);

  // 暗色主题颜色
  static const Color darkBackground = Color(0xFF0F172A);
  static const Color darkSurface = Color(0xFF1E293B);
  static const Color darkTextPrimary = Color(0xFFF1F5F9);
  static const Color darkTextSecondary = Color(0xFF94A3B8);
  static const Color darkTextTertiary = Color(0xFF64748B);
  static const Color darkDivider = Color(0xFF334155);
  static const Color darkBorder = Color(0xFF475569);

  // 圆角尺寸
  static const double radiusXs = 4.0;
  static const double radiusSm = 8.0;
  static const double radiusMd = 12.0;
  static const double radiusLg = 16.0;
  static const double radiusXl = 20.0;
  static const double radiusFull = 999.0;

  // 间距尺寸
  static const double spaceXs = 4.0;
  static const double spaceSm = 8.0;
  static const double spaceMd = 12.0;
  static const double spaceLg = 16.0;
  static const double spaceXl = 20.0;
  static const double space2xl = 24.0;

  // 文字样式
  static TextStyle _baseTextStyle(Color color) =>
      TextStyle(color: color, fontFamily: 'Inter');

  // 亮色主题
  static ThemeData lightTheme = ThemeData(
    useMaterial3: true,
    brightness: Brightness.light,
    colorScheme: ColorScheme.fromSeed(
      seedColor: primaryColor,
      brightness: Brightness.light,
      surface: lightSurface,
      error: errorColor,
    ),
    scaffoldBackgroundColor: lightBackground,
    fontFamily: 'Inter',

    // 文字主题
    textTheme: TextTheme(
      // 大标题
      headlineLarge: _baseTextStyle(
        lightTextPrimary,
      ).copyWith(fontSize: 28, fontWeight: FontWeight.bold, height: 1.3),
      headlineMedium: _baseTextStyle(
        lightTextPrimary,
      ).copyWith(fontSize: 24, fontWeight: FontWeight.bold, height: 1.3),
      headlineSmall: _baseTextStyle(
        lightTextPrimary,
      ).copyWith(fontSize: 20, fontWeight: FontWeight.w600, height: 1.3),
      // 标题
      titleLarge: _baseTextStyle(
        lightTextPrimary,
      ).copyWith(fontSize: 18, fontWeight: FontWeight.w600, height: 1.4),
      titleMedium: _baseTextStyle(
        lightTextPrimary,
      ).copyWith(fontSize: 16, fontWeight: FontWeight.w600, height: 1.4),
      titleSmall: _baseTextStyle(
        lightTextPrimary,
      ).copyWith(fontSize: 14, fontWeight: FontWeight.w600, height: 1.4),
      // 正文
      bodyLarge: _baseTextStyle(
        lightTextPrimary,
      ).copyWith(fontSize: 16, fontWeight: FontWeight.normal, height: 1.5),
      bodyMedium: _baseTextStyle(
        lightTextPrimary,
      ).copyWith(fontSize: 14, fontWeight: FontWeight.normal, height: 1.5),
      bodySmall: _baseTextStyle(
        lightTextSecondary,
      ).copyWith(fontSize: 12, fontWeight: FontWeight.normal, height: 1.5),
      // 标签
      labelLarge: _baseTextStyle(
        lightTextPrimary,
      ).copyWith(fontSize: 14, fontWeight: FontWeight.w500, height: 1.4),
      labelMedium: _baseTextStyle(
        lightTextSecondary,
      ).copyWith(fontSize: 12, fontWeight: FontWeight.w500, height: 1.4),
      labelSmall: _baseTextStyle(
        lightTextTertiary,
      ).copyWith(fontSize: 11, fontWeight: FontWeight.w500, height: 1.4),
    ),

    // AppBar 主题
    appBarTheme: const AppBarTheme(
      backgroundColor: lightBackground,
      foregroundColor: lightTextPrimary,
      elevation: 0,
      centerTitle: true,
      titleTextStyle: TextStyle(
        color: lightTextPrimary,
        fontSize: 18,
        fontWeight: FontWeight.w600,
        fontFamily: 'Inter',
      ),
      iconTheme: IconThemeData(color: lightTextPrimary, size: 24),
    ),

    // 卡片主题
    cardTheme: CardThemeData(
      color: lightSurface,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(radiusLg),
        side: const BorderSide(color: lightDivider, width: 1),
      ),
      margin: EdgeInsets.zero,
    ),

    // 按钮主题 - 主要按钮
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: primaryColor,
        foregroundColor: Colors.white,
        elevation: 0,
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusMd),
        ),
        textStyle: const TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w600,
          fontFamily: 'Inter',
        ),
      ),
    ),

    // 文字按钮
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: primaryColor,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusSm),
        ),
        textStyle: const TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w500,
          fontFamily: 'Inter',
        ),
      ),
    ),

    // 边框按钮
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: primaryColor,
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
        side: BorderSide(
          color: primaryColor.withValues(alpha: 0.5),
          width: 1.5,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusMd),
        ),
        textStyle: const TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w600,
          fontFamily: 'Inter',
        ),
      ),
    ),

    // 图标按钮
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(
        foregroundColor: lightTextSecondary,
        padding: const EdgeInsets.all(8),
      ),
    ),

    // 输入框主题
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: lightSurface,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(radiusMd),
        borderSide: const BorderSide(color: lightBorder),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(radiusMd),
        borderSide: const BorderSide(color: lightBorder),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(radiusMd),
        borderSide: BorderSide(color: primaryColor, width: 2),
      ),
      hintStyle: _baseTextStyle(lightTextTertiary).copyWith(fontSize: 14),
      labelStyle: _baseTextStyle(lightTextSecondary).copyWith(fontSize: 14),
    ),

    // 分割线
    dividerTheme: const DividerThemeData(
      color: lightDivider,
      thickness: 1,
      space: 1,
    ),
    dividerColor: lightDivider,

    // 底部导航栏
    bottomNavigationBarTheme: const BottomNavigationBarThemeData(
      backgroundColor: lightSurface,
      selectedItemColor: primaryColor,
      unselectedItemColor: lightTextSecondary,
      type: BottomNavigationBarType.fixed,
      elevation: 0,
      selectedLabelStyle: TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
      unselectedLabelStyle: TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w500,
      ),
    ),

    // 底部弹窗
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: lightSurface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(radiusXl)),
      ),
      elevation: 0,
    ),

    // 对话框
    dialogTheme: DialogThemeData(
      backgroundColor: lightSurface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(radiusXl),
      ),
      elevation: 0,
      titleTextStyle: _baseTextStyle(
        lightTextPrimary,
      ).copyWith(fontSize: 18, fontWeight: FontWeight.bold),
      contentTextStyle: _baseTextStyle(
        lightTextSecondary,
      ).copyWith(fontSize: 14),
    ),

    // Snackbar
    snackBarTheme: SnackBarThemeData(
      backgroundColor: darkSurface,
      contentTextStyle: _baseTextStyle(darkTextPrimary).copyWith(fontSize: 14),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(radiusMd),
      ),
      behavior: SnackBarBehavior.floating,
    ),

    // 进度指示器
    progressIndicatorTheme: const ProgressIndicatorThemeData(
      color: primaryColor,
      linearTrackColor: lightDivider,
      circularTrackColor: lightDivider,
    ),

    // Switch
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) return Colors.white;
        return lightTextTertiary;
      }),
      trackColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) return primaryColor;
        return lightDivider;
      }),
    ),

    // Checkbox
    checkboxTheme: CheckboxThemeData(
      fillColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) return primaryColor;
        return Colors.transparent;
      }),
      checkColor: WidgetStateProperty.all(Colors.white),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(radiusXs),
      ),
      side: const BorderSide(color: lightBorder, width: 1.5),
    ),

    // ListTile
    listTileTheme: const ListTileThemeData(
      contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      minLeadingWidth: 24,
      iconColor: lightTextSecondary,
      textColor: lightTextPrimary,
    ),

    // Chip
    chipTheme: ChipThemeData(
      backgroundColor: lightSurface,
      selectedColor: primaryColor.withValues(alpha: 0.15),
      labelStyle: _baseTextStyle(lightTextPrimary).copyWith(fontSize: 13),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(radiusSm),
        side: const BorderSide(color: lightBorder),
      ),
    ),
  );

  // 暗色主题
  static ThemeData darkTheme = ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    colorScheme: ColorScheme.fromSeed(
      seedColor: primaryColor,
      brightness: Brightness.dark,
      surface: darkSurface,
      error: errorColor,
    ),
    scaffoldBackgroundColor: darkBackground,
    fontFamily: 'Inter',

    // 文字主题
    textTheme: TextTheme(
      headlineLarge: _baseTextStyle(
        darkTextPrimary,
      ).copyWith(fontSize: 28, fontWeight: FontWeight.bold, height: 1.3),
      headlineMedium: _baseTextStyle(
        darkTextPrimary,
      ).copyWith(fontSize: 24, fontWeight: FontWeight.bold, height: 1.3),
      headlineSmall: _baseTextStyle(
        darkTextPrimary,
      ).copyWith(fontSize: 20, fontWeight: FontWeight.w600, height: 1.3),
      titleLarge: _baseTextStyle(
        darkTextPrimary,
      ).copyWith(fontSize: 18, fontWeight: FontWeight.w600, height: 1.4),
      titleMedium: _baseTextStyle(
        darkTextPrimary,
      ).copyWith(fontSize: 16, fontWeight: FontWeight.w600, height: 1.4),
      titleSmall: _baseTextStyle(
        darkTextPrimary,
      ).copyWith(fontSize: 14, fontWeight: FontWeight.w600, height: 1.4),
      bodyLarge: _baseTextStyle(
        darkTextPrimary,
      ).copyWith(fontSize: 16, fontWeight: FontWeight.normal, height: 1.5),
      bodyMedium: _baseTextStyle(
        darkTextPrimary,
      ).copyWith(fontSize: 14, fontWeight: FontWeight.normal, height: 1.5),
      bodySmall: _baseTextStyle(
        darkTextSecondary,
      ).copyWith(fontSize: 12, fontWeight: FontWeight.normal, height: 1.5),
      labelLarge: _baseTextStyle(
        darkTextPrimary,
      ).copyWith(fontSize: 14, fontWeight: FontWeight.w500, height: 1.4),
      labelMedium: _baseTextStyle(
        darkTextSecondary,
      ).copyWith(fontSize: 12, fontWeight: FontWeight.w500, height: 1.4),
      labelSmall: _baseTextStyle(
        darkTextTertiary,
      ).copyWith(fontSize: 11, fontWeight: FontWeight.w500, height: 1.4),
    ),

    appBarTheme: const AppBarTheme(
      backgroundColor: darkBackground,
      foregroundColor: darkTextPrimary,
      elevation: 0,
      centerTitle: true,
      titleTextStyle: TextStyle(
        color: darkTextPrimary,
        fontSize: 18,
        fontWeight: FontWeight.w600,
        fontFamily: 'Inter',
      ),
      iconTheme: IconThemeData(color: darkTextPrimary, size: 24),
    ),

    cardTheme: CardThemeData(
      color: darkSurface,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(radiusLg),
        side: const BorderSide(color: darkDivider, width: 1),
      ),
      margin: EdgeInsets.zero,
    ),

    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: primaryColor,
        foregroundColor: Colors.white,
        elevation: 0,
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusMd),
        ),
        textStyle: const TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w600,
          fontFamily: 'Inter',
        ),
      ),
    ),

    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: primaryColor,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusSm),
        ),
        textStyle: const TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w500,
          fontFamily: 'Inter',
        ),
      ),
    ),

    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: primaryColor,
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
        side: BorderSide(
          color: primaryColor.withValues(alpha: 0.5),
          width: 1.5,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusMd),
        ),
        textStyle: const TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w600,
          fontFamily: 'Inter',
        ),
      ),
    ),

    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(
        foregroundColor: darkTextSecondary,
        padding: const EdgeInsets.all(8),
      ),
    ),

    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: darkSurface,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(radiusMd),
        borderSide: const BorderSide(color: darkBorder),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(radiusMd),
        borderSide: const BorderSide(color: darkBorder),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(radiusMd),
        borderSide: BorderSide(color: primaryColor, width: 2),
      ),
      hintStyle: _baseTextStyle(darkTextTertiary).copyWith(fontSize: 14),
      labelStyle: _baseTextStyle(darkTextSecondary).copyWith(fontSize: 14),
    ),

    dividerTheme: const DividerThemeData(
      color: darkDivider,
      thickness: 1,
      space: 1,
    ),
    dividerColor: darkDivider,

    bottomNavigationBarTheme: const BottomNavigationBarThemeData(
      backgroundColor: darkSurface,
      selectedItemColor: primaryColor,
      unselectedItemColor: darkTextSecondary,
      type: BottomNavigationBarType.fixed,
      elevation: 0,
      selectedLabelStyle: TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
      unselectedLabelStyle: TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w500,
      ),
    ),

    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: darkSurface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(radiusXl)),
      ),
      elevation: 0,
    ),

    dialogTheme: DialogThemeData(
      backgroundColor: darkSurface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(radiusXl),
      ),
      elevation: 0,
      titleTextStyle: _baseTextStyle(
        darkTextPrimary,
      ).copyWith(fontSize: 18, fontWeight: FontWeight.bold),
      contentTextStyle: _baseTextStyle(
        darkTextSecondary,
      ).copyWith(fontSize: 14),
    ),

    snackBarTheme: SnackBarThemeData(
      backgroundColor: lightSurface,
      contentTextStyle: _baseTextStyle(lightTextPrimary).copyWith(fontSize: 14),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(radiusMd),
      ),
      behavior: SnackBarBehavior.floating,
    ),

    progressIndicatorTheme: const ProgressIndicatorThemeData(
      color: primaryColor,
      linearTrackColor: darkDivider,
      circularTrackColor: darkDivider,
    ),

    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) return Colors.white;
        return darkTextTertiary;
      }),
      trackColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) return primaryColor;
        return darkDivider;
      }),
    ),

    checkboxTheme: CheckboxThemeData(
      fillColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) return primaryColor;
        return Colors.transparent;
      }),
      checkColor: WidgetStateProperty.all(Colors.white),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(radiusXs),
      ),
      side: const BorderSide(color: darkBorder, width: 1.5),
    ),

    listTileTheme: const ListTileThemeData(
      contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      minLeadingWidth: 24,
      iconColor: darkTextSecondary,
      textColor: darkTextPrimary,
    ),

    chipTheme: ChipThemeData(
      backgroundColor: darkSurface,
      selectedColor: primaryColor.withValues(alpha: 0.15),
      labelStyle: _baseTextStyle(darkTextPrimary).copyWith(fontSize: 13),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(radiusSm),
        side: const BorderSide(color: darkBorder),
      ),
    ),
  );
}

// 扩展方法，方便获取自定义颜色和样式
extension ThemeExtension on BuildContext {
  // 主题判断
  bool get isDark => Theme.of(this).brightness == Brightness.dark;

  // 主色
  Color get primaryColor => Theme.of(this).colorScheme.primary;

  // 背景色
  Color get backgroundColor =>
      isDark ? AppTheme.darkBackground : AppTheme.lightBackground;

  Color get surfaceColor =>
      isDark ? AppTheme.darkSurface : AppTheme.lightSurface;

  // 文字颜色
  Color get textPrimary =>
      isDark ? AppTheme.darkTextPrimary : AppTheme.lightTextPrimary;

  Color get textSecondary =>
      isDark ? AppTheme.darkTextSecondary : AppTheme.lightTextSecondary;

  Color get textTertiary =>
      isDark ? AppTheme.darkTextTertiary : AppTheme.lightTextTertiary;

  // 分割线和边框
  Color get dividerColor =>
      isDark ? AppTheme.darkDivider : AppTheme.lightDivider;

  Color get borderColor => isDark ? AppTheme.darkBorder : AppTheme.lightBorder;

  // 语义色
  Color get successColor => AppTheme.successColor;
  Color get warningColor => AppTheme.warningColor;
  Color get errorColor => AppTheme.errorColor;
  Color get infoColor => AppTheme.infoColor;

  // 文字样式快捷方式
  TextTheme get textTheme => Theme.of(this).textTheme;

  // 圆角
  double get radiusXs => AppTheme.radiusXs;
  double get radiusSm => AppTheme.radiusSm;
  double get radiusMd => AppTheme.radiusMd;
  double get radiusLg => AppTheme.radiusLg;
  double get radiusXl => AppTheme.radiusXl;

  // 间距
  double get spaceXs => AppTheme.spaceXs;
  double get spaceSm => AppTheme.spaceSm;
  double get spaceMd => AppTheme.spaceMd;
  double get spaceLg => AppTheme.spaceLg;
  double get spaceXl => AppTheme.spaceXl;
  double get space2xl => AppTheme.space2xl;
}

// 常用组件样式扩展
extension AppButtonStyles on BuildContext {
  // 主要按钮样式
  ButtonStyle get primaryButtonStyle => ElevatedButton.styleFrom(
    backgroundColor: primaryColor,
    foregroundColor: Colors.white,
    elevation: 0,
    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(radiusMd),
    ),
  );

  // 次要按钮样式
  ButtonStyle get secondaryButtonStyle => ElevatedButton.styleFrom(
    backgroundColor: surfaceColor,
    foregroundColor: textPrimary,
    elevation: 0,
    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
    side: BorderSide(color: dividerColor),
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(radiusMd),
    ),
  );

  // 边框按钮样式
  ButtonStyle get outlineButtonStyle => OutlinedButton.styleFrom(
    foregroundColor: primaryColor,
    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
    side: BorderSide(color: primaryColor.withValues(alpha: 0.5), width: 1.5),
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(radiusMd),
    ),
  );

  // 胶囊按钮样式
  ButtonStyle get pillButtonStyle => ElevatedButton.styleFrom(
    backgroundColor: primaryColor,
    foregroundColor: Colors.white,
    elevation: 0,
    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(AppTheme.radiusFull),
    ),
  );
}

// 卡片装饰扩展
extension AppDecorations on BuildContext {
  // 标准卡片装饰
  BoxDecoration get cardDecoration => BoxDecoration(
    color: surfaceColor,
    borderRadius: BorderRadius.circular(radiusLg),
    border: Border.all(color: dividerColor),
  );

  // 带阴影的卡片装饰
  BoxDecoration get elevatedCardDecoration => BoxDecoration(
    color: surfaceColor,
    borderRadius: BorderRadius.circular(radiusLg),
    boxShadow: [
      BoxShadow(
        color: Colors.black.withValues(alpha: isDark ? 0.3 : 0.08),
        blurRadius: 16,
        offset: const Offset(0, 4),
      ),
    ],
  );

  // 圆形容器装饰
  BoxDecoration circleDecoration({Color? color}) => BoxDecoration(
    color: color ?? surfaceColor,
    shape: BoxShape.circle,
    border: Border.all(color: dividerColor),
  );
}
