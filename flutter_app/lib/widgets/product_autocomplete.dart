import 'package:flutter/material.dart';

import '../data/models/view_models.dart';
import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';

/// Reference field with a search-as-you-type dropdown of products.
class ProductAutocomplete extends StatefulWidget {
  final List<ProductOverview> products;
  final TextEditingController controller;
  final ValueChanged<ProductOverview> onSelected;
  final String labelText;

  const ProductAutocomplete({
    super.key,
    required this.products,
    required this.controller,
    required this.onSelected,
    this.labelText = 'Référence *',
  });

  @override
  State<ProductAutocomplete> createState() => _ProductAutocompleteState();
}

class _ProductAutocompleteState extends State<ProductAutocomplete> {
  final _focusNode = FocusNode();

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Autocomplete<ProductOverview>(
      textEditingController: widget.controller,
      focusNode: _focusNode,
      displayStringForOption: (o) => '${o.product.reference} — ${o.product.designation}',
      optionsBuilder: (textEditingValue) {
        final query = textEditingValue.text.trim().toLowerCase();
        if (query.isEmpty) return const Iterable<ProductOverview>.empty();
        return widget.products.where((o) =>
            o.product.reference.toLowerCase().contains(query) ||
            o.product.designation.toLowerCase().contains(query));
      },
      onSelected: widget.onSelected,
      fieldViewBuilder: (context, fieldController, focusNode, onFieldSubmitted) {
        return TextField(
          controller: fieldController,
          focusNode: focusNode,
          decoration: InputDecoration(labelText: widget.labelText, hintText: 'Chercher produit…'),
        );
      },
      optionsViewBuilder: (context, onSelectedOption, options) {
        return Align(
          alignment: Alignment.topLeft,
          child: Material(
            color: AppColors.surface,
            elevation: 4,
            borderRadius: BorderRadius.circular(8),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 220, maxWidth: 320),
              child: ListView.builder(
                padding: EdgeInsets.zero,
                shrinkWrap: true,
                itemCount: options.length,
                itemBuilder: (context, index) {
                  final option = options.elementAt(index);
                  return ListTile(
                    dense: true,
                    title: Text(
                      '${option.product.reference} — ${option.product.designation}',
                      style: AppTextStyles.body,
                      overflow: TextOverflow.ellipsis,
                    ),
                    onTap: () => onSelectedOption(option),
                  );
                },
              ),
            ),
          ),
        );
      },
    );
  }
}
