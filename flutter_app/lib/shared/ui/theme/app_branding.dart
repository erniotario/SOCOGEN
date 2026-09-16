/// What the product calls itself.
///
/// The application was named after its first customer, SOCOGEN, which
/// stopped being true once a second business could install it: a
/// wholesaler in Douala should not run software wearing a competitor's
/// name. The customer's own name is *data* now -- `company_settings`,
/// filled in at first run -- and appears on their documents and reports.
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

  /// Short form, as it appears on the executable, the installer and the
  /// sidebar. Stands for Store Management.
  static const String productName = 'SM';

  /// What the product does, in the language its users read.
  static const String tagline = 'Gestion de Stock';

  /// Desktop window title, and the title of the Flutter application.
  static const String windowTitle = '$productName — $tagline';
}
