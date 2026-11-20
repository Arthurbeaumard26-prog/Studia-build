import SwiftUI
import WebKit

/// Connexion unique : webview intégrée ouverte sur la version mobile de Pronote
/// du collège Françoise Dolto, avec passage par ÉduConnect.
/// La webview sert uniquement à la connexion : l'interface reste native.
struct LoginView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            header

            PronoteWebView(
                onSessionReady: { cookieStore in
                    Task { await model.completeLogin(cookieStore: cookieStore) }
                }
            )
        }
        .background(Color(Theme.background).ignoresSafeArea())
        .preferredColorScheme(.dark)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Studia")
                .font(.system(.largeTitle, design: .rounded).weight(.bold))
                .foregroundStyle(Color(Theme.accent))
            Text("Connecte-toi une seule fois via ÉduConnect. Studia récupérera ensuite toutes tes données automatiquement.")
                .font(.subheadline)
                .foregroundStyle(Color(Theme.textSecondary))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 20)
        .padding(.top, 24)
        .padding(.bottom, 12)
    }
}

/// WebView ouverte sur mobile.html, avec détection de fin de connexion.
struct PronoteWebView: UIViewRepresentable {
    var onSessionReady: (WKHTTPCookieStore) -> Void

    private let processPool = WebViewProcessPool.shared

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.processPool = processPool
        config.websiteDataStore = .default()
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.allowsBackForwardNavigationGestures = true
        webView.scrollView.isScrollEnabled = true
        context.coordinator.webView = webView
        context.coordinator.onSessionReady = onSessionReady
        let request = URLRequest(url: PronoteSession.mobileURL)
        webView.load(request)
        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}

    func makeCoordinator() -> Coordinator {
        let c = Coordinator()
        c.onSessionReady = onSessionReady
        return c
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        var onSessionReady: ((WKHTTPCookieStore) -> Void)?
        weak var webView: WKWebView?
        private var detected = false

        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) { }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            checkSession(webView)
        }

        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                     decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            decisionHandler(.allow)
        }

        private func checkSession(_ webView: WKWebView) {
            guard !detected, let url = webView.url else { return }
            let host = url.host ?? ""
            guard host == "0170010u.index-education.net" else { return }
            let isPronote = url.absoluteString.lowercased().contains("/pronote")
            guard isPronote else { return }

            // Si la page affichée n'est plus un écran d'identification,
            // la session Pronote est active.
            webView.evaluateJavaScript("document.body.innerText.slice(0, 4000)") { [weak self] result, _ in
                guard let self else { return }
                guard let text = result as? String else { return }
                let folded = text.folding(options: .diacriticInsensitive, locale: Locale(identifier: "fr_FR")).lowercased()
                let loggedOut = folded.contains("mot de passe") || folded.contains("connexion") || folded.contains("choisis")
                guard !loggedOut else { return }
                self.detected = true
                if let store = self.webView?.configuration.websiteDataStore.httpCookieStore {
                    self.onSessionReady?(store)
                }
            }
        }
    }
}

final class WebViewProcessPool {
    static let shared = WKProcessPool()
}
