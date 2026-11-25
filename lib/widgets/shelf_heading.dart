import 'package:flutter/material.dart';

class ShelfHeading extends StatelessWidget {
  const ShelfHeading(this.title, {super.key, required this.fontSize, this.color});

  final String title;
  final double fontSize;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      header: true,
      child: Text(
        title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: Theme.of(context).textTheme.titleLarge?.copyWith(
          color: color,
          fontSize: fontSize,
          fontWeight: FontWeight.w400,
          letterSpacing: -0.025 * fontSize,
          height: 1.15,
        ),
      ),
    );
  }
}
