import 'package:flutter/material.dart';

import '../data/models/view_models.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
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
    // The options popup is an overlay, so it cannot measure the field
    // itself; capture the field's width here and hand it down so the
    // dropdown lines up with the input instead of using a fixed 320px.
    return LayoutBuilder(
      builder: (context, constraints) => _buildAutocomplete(
        context,
        constraints.maxWidth,
      ),
    );
  }

  Widget _buildAutocomplete(BuildContext context, double fieldWidth) {
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
          child: Container(
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(AppRadius.lg),
              border: Border.all(color: AppColors.borderStrong),
              boxShadow: AppShadows.medium,
            ),
            clipBehavior: Clip.antiAlias,
            // The options are ListTiles, which paint their highlight and
            // ink splash on the nearest Material ancestor. Without one
            // inside this coloured box that ancestor is the page behind
            // the overlay, so the box hides every splash and the options
            // feel dead to the touch. A transparent Material here keeps
            // the surface colour above and gives the tiles something to
            // paint on.
            child: Material(
              type: MaterialType.transparency,
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: 260,
                  maxWidth: fieldWidth,
                ),
                child: ListView.builder(
                  padding: EdgeInsets.zero,
                  shrinkWrap: true,
                  itemCount: options.length,
                  itemBuilder: (context, index) {
                    final option = options.elementAt(index);
                    return ListTile(
                      dense: true,
                      title: Text(
                        '${option.product.reference} — '
                        '${option.product.designation}',
                        style: AppTextStyles.body,
                        overflow: TextOverflow.ellipsis,
                      ),
                      onTap: () => onSelectedOption(option),
                    );
                  },
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
