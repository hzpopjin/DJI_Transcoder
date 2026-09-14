import SwiftUI
import WebKit

struct PrivacyPolicyView: View {
    var body: some View {
        Group {
            if let url = Bundle.main.url(forResource: "PrivacyPolicy", withExtension: "html") {
                LocalPrivacyWebView(url: url)
            } else {
                ContentUnavailableView {
                    Label("暂时无法显示隐私政策", systemImage: "doc.text")
                } description: {
                    Text("请联系 service@randomdance.cn 获取隐私政策。")
                } actions: {
                    if let emailURL = URL(string: "mailto:service@randomdance.cn") {
                        Link("联系开发者", destination: emailURL)
                    }
                }
            }
        }
        .navigationTitle("隐私政策")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct LocalPrivacyWebView: UIViewRepresentable {
    let url: URL

    func makeCoordinator() -> Coordinator { Coordinator(url: url) }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = false
        let view = WKWebView(frame: .zero, configuration: configuration)
        view.navigationDelegate = context.coordinator
        view.loadFileURL(url, allowingReadAccessTo: url)
        return view
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}

    final class Coordinator: NSObject, WKNavigationDelegate {
        private let url: URL

        init(url: URL) { self.url = url }

        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
        ) {
            guard let destination = navigationAction.request.url else {
                decisionHandler(.cancel)
                return
            }
            if destination.isFileURL, destination.standardizedFileURL.path == url.standardizedFileURL.path {
                decisionHandler(.allow)
            } else {
                decisionHandler(.cancel)
                if navigationAction.navigationType == .linkActivated, destination.scheme == "mailto" {
                    UIApplication.shared.open(destination)
                }
            }
        }
    }
}
