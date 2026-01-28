import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:get/get.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart'; // Needed for AuthUser model

// ==========================================
// CONFIGURATION & COLORS
// ==========================================

class AppColors {
  static const Color pageBG = Color(0xFFFFFFFF);
  static const Color grey = Color(0xFFECF0F1);
  static const Color mainColor = Color(0xFF3498DB);
  static const Color lightMainColor = Color(0xFF5FA2DD);
  static const Color lightMainColor2 = Color(0xFFB0CBF5);
  static const Color smallText = Color(0xFF546175);
  static Color lightYellow = Colors.yellow.shade100;
  static Color mapColor = Colors.green.shade100;
  static Color lightRed = const Color(0xffEF8A80);
  static const Color slateGrey = Color(0xFF95A5A6);
  static const Color primaryBlack = Color(0xFF1B1A17);
  static const Color darkGrey = Color(0xFF3A4855);
  static const Color textBoxPlaceholder = Color(0xFFa8a8a7);
}

class Dimensions {
  static double screenHeight = Get.context?.height ?? 803;
  static double screenWidth = Get.context?.width ?? 392;
  static double height10 = screenHeight / 80.3;
  static double width10 = screenWidth / 39.28;
  static double radius10 = screenHeight / 80.3;
}

// ==========================================
// SHARED MODELS
// ==========================================

@immutable
class AuthUser {
  final bool isEmailVerified;
  const AuthUser({required this.isEmailVerified});
  factory AuthUser.fromFirebase(User user) =>
      AuthUser(isEmailVerified: user.emailVerified);
}

// ==========================================
// SHARED WIDGETS
// ==========================================

class MySnackBar {
  void mySnackBar(
      {required String header,
      required String content,
      Color bgColor = Colors.white,
      Color borderColor = Colors.white}) {
    Get.snackbar(header, content,
        backgroundColor: bgColor,
        borderColor: borderColor,
        borderWidth: 1,
        borderRadius: 20,
        duration: const Duration(seconds: 3));
  }
}

class BlueButton extends StatelessWidget {
  final VoidCallback onPressed;
  final String text;
  final double width;
  final Color color;
  final Color textColor;
  final double height;
  final FontWeight fontweight;
  final double fontSize;

  const BlueButton(
      {super.key,
      required this.onPressed,
      required this.text,
      this.width = double.infinity,
      this.color = AppColors.mainColor,
      this.textColor = AppColors.grey,
      this.height = 60,
      this.fontweight = FontWeight.bold,
      this.fontSize = 18});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
        width: width,
        child: MaterialButton(
            onPressed: onPressed,
            textColor: textColor,
            color: color,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            height: height,
            child: Text(text,
                style: TextStyle(fontWeight: fontweight, fontSize: fontSize))));
  }
}

class BigText extends StatelessWidget {
  final String text;
  final Color? color;
  final double size;
  final FontWeight weight;
  final TextAlign align;
  const BigText(
      {super.key,
      required this.text,
      required this.color,
      this.size = 40,
      this.weight = FontWeight.w700,
      this.align = TextAlign.center});
  @override
  Widget build(BuildContext context) {
    return Text(text,
        textAlign: align,
        style: TextStyle(color: color, fontSize: size, fontWeight: weight));
  }
}

class SmallText extends StatelessWidget {
  final Color? color;
  final String text;
  final double size;
  final FontWeight weight;
  final TextAlign align;
  const SmallText(
      {super.key,
      required this.text,
      this.color = AppColors.slateGrey,
      this.size = 18,
      this.weight = FontWeight.w500,
      this.align = TextAlign.left});
  @override
  Widget build(BuildContext context) {
    return Text(text,
        textAlign: align,
        style: TextStyle(color: color, fontSize: size, fontWeight: weight));
  }
}

class BackIcon extends StatelessWidget {
  const BackIcon({super.key});
  @override
  Widget build(BuildContext context) {
    return IconButton(
      onPressed: () => Navigator.of(context).pop(),
      icon: Icon(
        PhosphorIcons.arrowLeft(PhosphorIconsStyle.regular),
        color: AppColors.primaryBlack,
        size: 40,
      ),
    );
  }
}

class SquareTile extends StatelessWidget {
  final VoidCallback? onTap;
  final String imagePath;
  final double height;
  const SquareTile(
      {super.key,
      required this.imagePath,
      required this.onTap,
      required this.height});
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
        onTap: onTap, child: SvgPicture.asset(imagePath, height: height));
  }
}

// Common Input Decoration
class MyDecoration {
  InputDecoration getDecoration(
      {required IconData icon,
      required Widget label,
      required String hintText}) {
    return InputDecoration(
      prefixIcon: Icon(icon, color: AppColors.mainColor),
      label: label,
      hintText: hintText,
      fillColor: AppColors.grey,
      filled: true,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
    );
  }
}
