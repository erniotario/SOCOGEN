/// What the product calls itself.
///
/// The application was named after its first customer, which stopped
/// being true once a second business could install it: a wholesaler in
/// Douala should not run software wearing a competitor's name. The
/// customer's own name is *data* -- `company_settings`, filled in at
/// first run -- and is what the interface shows, on the sidebar, in the
/// window title and on every document. What is below is the product
/// underneath it, shown when the business has not been named yet.
/// This is the product above it.
///
/// Kept in one place so the next rename is one line rather than a hunt.
/// Three identifiers deliberately do NOT follow it, because they are
/// identity rather than branding, and changing them would strand an
/// installed customer:
///
///   * `DatabaseService._dbFileName` (`socogen_stock.db`) -- on Windows
///     the database sits beside the executable, so a new filename reads
///     as a brand-new install with no stock in it.
///   * `AppId` in `installer.iss` -- Inno Setup upgrades in place only
///     while it matches; change it and the next installer lands a second
///     copy alongside the first.
///   * `applicationId` in the Android Gradle config -- the identity Play
///     and the device use to recognise an update.
class AppBranding {
  AppBranding._();

  /// Nom du produit, tel qu'il apparaît sur l'exécutable, l'installeur
  /// et derrière le nom de l'entreprise dans la barre latérale.
  ///
  /// Générique à dessein : ce logiciel n'appartient plus à son premier
  /// client, et chaque entreprise qui l'installe y voit **son** nom, pas
  /// celui d'une autre. Le nom du produit n'est là que pour dire de quel
  /// logiciel il s'agit quand l'entreprise n'a pas encore été nommée.
  static const String productName = 'ERP';

  /// Ce que le produit fait, dans la langue de ceux qui l'utilisent.
  ///
  /// « Gestion commerciale » et non « Gestion de stock » : il tient le
  /// catalogue, les tiers, la caisse et les règlements, et s'annoncer
  /// plus petit qu'on est induit en erreur autant que l'inverse.
  static const String tagline = 'Gestion commerciale';

  /// Desktop window title, and the title of the Flutter application.
  static const String windowTitle = '$productName — $tagline';
}
