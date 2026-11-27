import SwiftUI
import UIKit

// MARK: - Lume Chrome · layout central (topo, base e teclado)
//
// Tudo que decide "onde o conteúdo pode ficar" mora aqui, para nenhuma tela esconder botão:
//  • TOPO  — `.lumeDetailChrome(title:)`: cabeçalho padrão (voltar + título compacto + ações) como
//            `safeAreaInset(edge: .top)`; o conteúdo começa ABAIXO dele e o título grande, ao sair da
//            tela, reaparece compacto no cabeçalho.
//  • BASE  — `.lumeTabScroll()`: espaço no fim = barra de abas + mini player (se houver) + margem.
//  • TECLADO — toque no fundo fecha, arrastar a lista fecha, barra "OK" sobre o teclado
//            (LumeKeyboard, instalado uma vez no app inteiro).

enum LumeLayout {
  /// Cápsula de abas (62) + respiro de 2 do BottomBar.
  static let tabBarHeight: CGFloat = 64
  /// Mini player (60) + espaçamento (10).
  static let miniPlayerHeight: CGFloat = 70
  /// Folga final para o último item subir bem acima da barra e do mini player.
  static let endMargin: CGFloat = 36
  /// Altura da linha do cabeçalho de detalhe.
  static let headerHeight: CGFloat = 56

  static func bottomInset(hasMiniPlayer: Bool) -> CGFloat {
    tabBarHeight + (hasMiniPlayer ? miniPlayerHeight : 0) + endMargin
  }
}

private struct LumeHasMiniPlayerKey: EnvironmentKey { static let defaultValue = false }

extension EnvironmentValues {
  /// `true` quando há música tocando (o mini player está visível acima da barra de abas).
  var lumeHasMiniPlayer: Bool {
    get { self[LumeHasMiniPlayerKey.self] }
    set { self[LumeHasMiniPlayerKey.self] = newValue }
  }
}

// MARK: - Base: espaço para barra de abas + mini player

private struct LumeTabScrollModifier: ViewModifier {
  @State private var hasMini = AudioPlayer.shared.currentTrack != nil
  @ObservedObject private var keyboard = KeyboardState.shared

  func body(content: Content) -> some View {
    content
      .safeAreaInset(edge: .bottom, spacing: 0) {
        // Com o teclado aberto a barra flutuante fica atrás dele: só sobra uma folga pequena.
        Color.clear
          .frame(height: keyboard.visible ? 16 : LumeLayout.bottomInset(hasMiniPlayer: hasMini))
          .allowsHitTesting(false)
          .accessibilityHidden(true)
      }
      .scrollDismissesKeyboard(.interactively)
      .onReceive(AudioPlayer.shared.$currentTrack.map { $0 != nil }.removeDuplicates()) { hasMini = $0 }
  }
}

/// Espaço no fim de listas/rolagens verticais para o último item ficar acima da barra e do mini player.
/// Aplique no próprio ScrollView/List (não em contêineres), para não afetar rolagens horizontais internas.
private struct LumeSheetScrollModifier: ViewModifier {
  func body(content: Content) -> some View {
    content
      .scrollDismissesKeyboard(.interactively)
      .scrollBounceBehavior(.basedOnSize)
  }
}

extension View {
  /// Rolagem de aba/detalhe: fim livre da barra flutuante + teclado some ao arrastar.
  func lumeTabScroll() -> some View { modifier(LumeTabScrollModifier()) }

  /// Rolagem dentro de sheets/pop-ups: não "balança" quando cabe, e o teclado some ao arrastar.
  func lumeSheetScroll() -> some View { modifier(LumeSheetScrollModifier()) }

  /// Cabeçalho padrão de telas empilhadas (voltar à esquerda, título compacto, ações à direita).
  /// - Parameters:
  ///   - title: título compacto (aparece com fade depois que o título grande rolou para fora).
  ///   - alwaysShowTitle: mostra o título desde o início (telas sem título grande no conteúdo).
  ///   - threshold: quanto rolar (pt) antes do título compacto aparecer.
  ///   - veilAfter: quanto rolar (pt) antes do véu (fundo que esconde o conteúdo sob a barra de status) aparecer;
  ///     telas com foto/hero no topo usam um valor maior para a foto ficar limpa até rolar.
  ///   - trailing: botões de ação à direita (cada um com alvo ≥ 44 pt).
  func lumeDetailChrome<T: View>(
    title: String,
    alwaysShowTitle: Bool = false,
    threshold: CGFloat = 72,
    veilAfter: CGFloat = 4,
    @ViewBuilder trailing: () -> T
  ) -> some View {
    modifier(LumeDetailChrome(title: title, alwaysShowTitle: alwaysShowTitle, threshold: threshold, veilAfter: veilAfter, trailing: trailing()))
  }

  func lumeDetailChrome(title: String, alwaysShowTitle: Bool = false, threshold: CGFloat = 72, veilAfter: CGFloat = 4) -> some View {
    lumeDetailChrome(title: title, alwaysShowTitle: alwaysShowTitle, threshold: threshold, veilAfter: veilAfter) { EmptyView() }
  }
}

// MARK: - Topo: cabeçalho de detalhe

struct LumeDetailChrome<Trailing: View>: ViewModifier {
  let title: String
  let alwaysShowTitle: Bool
  let threshold: CGFloat
  let veilAfter: CGFloat
  let trailing: Trailing
  /// 0 = no topo · 1 = rolou um pouco (véu) · 2 = título grande saiu (título compacto).
  @State private var level = 0

  func body(content: Content) -> some View {
    content
      .onScrollGeometryChange(for: Int?.self) { g in
        // Ignora ScrollViews horizontais internos (HRow, chips, discografia) para que rolar lateralmente
        // nunca apague o véu nem o título compacto do cabeçalho.
        let scrollsVertically = g.contentSize.height > g.containerSize.height + 1
        let scrollsHorizontallyOnly = !scrollsVertically && g.contentSize.width > g.containerSize.width + 1
        if scrollsHorizontallyOnly { return nil }
        let y = g.contentOffset.y + g.contentInsets.top
        return y > threshold ? 2 : (y > veilAfter ? 1 : 0)
      } action: { _, now in
        guard let now else { return }
        withAnimation(.easeOut(duration: 0.22)) { level = now }
      }
      .toolbar(.hidden, for: .navigationBar)
      .safeAreaInset(edge: .top, spacing: 0) {
        DetailHeader(title: title, showTitle: alwaysShowTitle || level >= 2, veil: level >= 1 || alwaysShowTitle, trailing: trailing)
      }
      .background(SwipeBackEnabler().frame(width: 0, height: 0))
  }
}

/// Linha de vidro: voltar · título compacto (fade) · ações.
struct DetailHeader<Trailing: View>: View {
  let title: String
  let showTitle: Bool
  let veil: Bool
  let trailing: Trailing
  @Environment(\.dismiss) private var dismiss

  var body: some View {
    HStack(spacing: 10) {
      GlassIconButton(systemName: "chevron.left", size: 44, iconSize: 17) { dismiss() }
        .accessibilityLabel("Voltar")

      Text(title)
        .font(Theme.font(16, .semibold))
        .foregroundStyle(Theme.text)
        .lineLimit(1)
        .minimumScaleFactor(0.8)
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity)
        .frame(height: 38)
        .glassCapsule()
        .opacity(showTitle && !title.isEmpty ? 1 : 0)
        .allowsHitTesting(false)
        .accessibilityHidden(!showTitle)

      trailing
    }
    .glassGroup(spacing: 12)
    .padding(.horizontal, 16)
    .frame(height: LumeLayout.headerHeight)
    .background(alignment: .top) {
      // Véu: o conteúdo rolado some suavemente sob o cabeçalho (e sob a barra de status).
      Rectangle()
        .fill(Theme.canvas)
        .mask(
          LinearGradient(
            stops: [
              .init(color: .black, location: 0),
              .init(color: .black.opacity(0.98), location: 0.78),
              .init(color: .black.opacity(0), location: 1),
            ],
            startPoint: .top, endPoint: .bottom)
        )
        .padding(.bottom, -20)
        .ignoresSafeArea(edges: .top)
        .opacity(veil ? 1 : 0)
        .allowsHitTesting(false)
    }
    .zIndex(5)
  }
}

/// Título grande no conteúdo (telas que antes usavam `navigationTitle` grande).
struct LumeLargeTitle: View {
  let text: String
  var subtitle: String? = nil

  init(_ text: String, subtitle: String? = nil) {
    self.text = text
    self.subtitle = subtitle
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 4) {
      Text(text)
        .font(Theme.font(34, .bold))
        .foregroundStyle(Theme.text)
        .lineLimit(3)
        .minimumScaleFactor(0.7)
      if let subtitle {
        Text(subtitle)
          .font(Theme.font(14))
          .foregroundStyle(Theme.secondary)
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(.horizontal, 20)
    .padding(.top, 2)
    .padding(.bottom, 10)
    .accessibilityAddTraits(.isHeader)
  }
}

/// Mantém o gesto de arrastar da borda esquerda para voltar, mesmo com a barra de navegação escondida.
private struct SwipeBackEnabler: UIViewControllerRepresentable {
  func makeUIViewController(context: Context) -> Holder { Holder() }
  func updateUIViewController(_ vc: Holder, context: Context) {}

  final class Holder: UIViewController {
    override func didMove(toParent parent: UIViewController?) {
      super.didMove(toParent: parent)
      DispatchQueue.main.async { [weak self] in
        guard let nav = self?.navigationController else { return }
        nav.interactivePopGestureRecognizer?.delegate = SwipeBackDelegate.shared
        nav.interactivePopGestureRecognizer?.isEnabled = true
      }
    }
    override func viewDidAppear(_ animated: Bool) {
      super.viewDidAppear(animated)
      if let nav = navigationController {
        nav.interactivePopGestureRecognizer?.delegate = SwipeBackDelegate.shared
        nav.interactivePopGestureRecognizer?.isEnabled = true
      }
    }
  }
}

private final class SwipeBackDelegate: NSObject, UIGestureRecognizerDelegate {
  static let shared = SwipeBackDelegate()
  func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
    guard let nav = (gestureRecognizer.view?.next as? UIViewController)?.navigationController
            ?? gestureRecognizer.view?.parentNavigationController else { return true }
    return nav.viewControllers.count > 1
  }
}

private extension UIView {
  var parentNavigationController: UINavigationController? {
    var r: UIResponder? = self
    while let n = r {
      if let nav = n as? UINavigationController { return nav }
      r = n.next
    }
    return nil
  }
}

// MARK: - Teclado

/// Instalado uma vez no app:
///  1. toque fora de um campo de texto fecha o teclado (sem roubar o toque dos botões);
///  2. todo campo de texto ganha a barra "OK" sobre o teclado.
@MainActor
enum LumeKeyboard {
  private static var installed = false
  private static let tapDelegate = KeyboardTapDelegate()
  private static var windowsWithTap = NSHashTable<UIWindow>.weakObjects()

  static func install() {
    guard !installed else { attachToWindows(); return }
    installed = true
    let nc = NotificationCenter.default
    nc.addObserver(forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main) { _ in
      MainActor.assumeIsolated { attachToWindows() }
    }
    nc.addObserver(forName: UIWindow.didBecomeKeyNotification, object: nil, queue: .main) { _ in
      MainActor.assumeIsolated { attachToWindows() }
    }
    nc.addObserver(forName: UITextField.textDidBeginEditingNotification, object: nil, queue: .main) { note in
      guard let f = note.object as? UITextField else { return }
      MainActor.assumeIsolated { addDoneBar(to: f) }
    }
    nc.addObserver(forName: UITextView.textDidBeginEditingNotification, object: nil, queue: .main) { note in
      guard let v = note.object as? UITextView, v.isEditable else { return }
      MainActor.assumeIsolated { addDoneBar(to: v) }
    }
    attachToWindows()
  }

  static func dismiss() {
    UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
  }

  private static func attachToWindows() {
    for scene in UIApplication.shared.connectedScenes {
      guard let ws = scene as? UIWindowScene else { continue }
      for w in ws.windows where !windowsWithTap.contains(w) {
        let tap = UITapGestureRecognizer(target: tapDelegate, action: #selector(KeyboardTapDelegate.handle(_:)))
        tap.cancelsTouchesInView = false
        tap.delaysTouchesBegan = false
        tap.delaysTouchesEnded = false
        tap.delegate = tapDelegate
        w.addGestureRecognizer(tap)
        windowsWithTap.add(w)
      }
    }
  }

  private static func addDoneBar<V: UIView & UITextInputTraits>(to field: V) {
    guard let responder = field as? UIResponder, responder.inputAccessoryView == nil else { return }
    let bar = UIToolbar(frame: CGRect(x: 0, y: 0, width: 320, height: 44))
    bar.autoresizingMask = .flexibleWidth
    let done = UIBarButtonItem(title: "OK", style: .done, target: tapDelegate, action: #selector(KeyboardTapDelegate.done))
    bar.items = [UIBarButtonItem(systemItem: .flexibleSpace), done]
    bar.sizeToFit()
    if let tf = field as? UITextField { tf.inputAccessoryView = bar; tf.reloadInputViews() }
    else if let tv = field as? UITextView { tv.inputAccessoryView = bar; tv.reloadInputViews() }
  }
}

/// Estado do teclado (visível/altura) para telas que precisam se compactar enquanto ele está aberto.
@MainActor
final class KeyboardState: ObservableObject {
  static let shared = KeyboardState()
  @Published private(set) var height: CGFloat = 0
  var visible: Bool { height > 80 }

  private init() {
    let nc = NotificationCenter.default
    nc.addObserver(forName: UIResponder.keyboardWillChangeFrameNotification, object: nil, queue: .main) { [weak self] n in
      let frame = (n.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect) ?? .zero
      let screen = UIScreen.main.bounds
      let h = max(0, screen.maxY - frame.minY)
      MainActor.assumeIsolated { self?.height = h }
    }
    nc.addObserver(forName: UIResponder.keyboardWillHideNotification, object: nil, queue: .main) { [weak self] _ in
      MainActor.assumeIsolated { self?.height = 0 }
    }
  }
}

private final class KeyboardTapDelegate: NSObject, UIGestureRecognizerDelegate {
  private var editingAtTouchStart: UIResponder?

  func gestureRecognizer(_ g: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
    editingAtTouchStart = UIResponder.lmCurrentFirstResponder()
    guard editingAtTouchStart is UITextField || editingAtTouchStart is UITextView else { return false }
    var v: UIView? = touch.view
    while let x = v {
      if x is UITextField || x is UITextView || x is UIToolbar { return false }
      v = x.superview
    }
    return true
  }

  func gestureRecognizer(_ g: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool { true }

  @objc func handle(_ g: UITapGestureRecognizer) {
    guard g.state == .ended, let before = editingAtTouchStart else { return }
    // Espera o botão tocado agir: se ele moveu o foco para outro campo, não fecha.
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.06) {
      if UIResponder.lmCurrentFirstResponder() === before { UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil) }
    }
  }

  @objc func done() {
    UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
  }
}

private extension UIResponder {
  nonisolated(unsafe) static weak var lmFound: UIResponder?
  static func lmCurrentFirstResponder() -> UIResponder? {
    lmFound = nil
    UIApplication.shared.sendAction(#selector(UIResponder.lmCapture), to: nil, from: nil, for: nil)
    return lmFound
  }
  @objc func lmCapture() { UIResponder.lmFound = self }
}
