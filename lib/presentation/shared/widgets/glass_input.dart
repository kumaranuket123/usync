import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';

class GlassInput extends StatefulWidget {
  const GlassInput({
    super.key,
    this.label,
    required this.hint,
    this.prefixIcon,
    this.obscure     = false,
    this.controller,
    this.keyboardType,
    this.onChanged,
    this.maxLength,
  });

  final String?              label;
  final String               hint;
  final String?              prefixIcon;
  final bool                 obscure;
  final TextEditingController? controller;
  final TextInputType?       keyboardType;
  final ValueChanged<String>? onChanged;
  final int?                 maxLength;

  @override
  State<GlassInput> createState() => _GlassInputState();
}

class _GlassInputState extends State<GlassInput> {
  late bool _obscure;

  @override
  void initState() {
    super.initState();
    _obscure = widget.obscure;
  }

  @override
  Widget build(BuildContext context) {

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (widget.label != null) ...[
          Text(widget.label!.toUpperCase(), style: AppTextStyles.labelCaps),
          const SizedBox(height: 8),
        ],
        TextField(
          controller:   widget.controller,
          obscureText:  _obscure,
          keyboardType: widget.keyboardType,
          onChanged:    widget.onChanged,
          maxLength:    widget.maxLength,
          style:        AppTextStyles.bodyLarge,
          decoration: InputDecoration(
            hintText:    widget.hint,
            counterText: '',
            prefixIcon:  widget.prefixIcon != null
                ? Padding(
                    padding: const EdgeInsets.all(14),
                    child:   Text(widget.prefixIcon!, style: const TextStyle(fontSize: 18)),
                  )
                : null,
            suffixIcon: widget.obscure
                ? IconButton(
                    onPressed: () => setState(() => _obscure = !_obscure),
                    icon: Icon(
                      _obscure ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                      color: AppColors.textMuted,
                      size: 20,
                    ),
                  )
                : null,
          ),
        ),
      ],
    );
  }
}
