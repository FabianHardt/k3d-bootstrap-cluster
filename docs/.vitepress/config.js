
const ref = "main";
const base =  "/k3d-bootstrap-cluster/"

export default {
    // site-level options
    title: 'K3d Bootstrap Cluster',
    description: 'A local kubernetes cluster for demo and showcase purposes',

    base: base,
    themeConfig: {
        lastUpdated: true,
        appRef: ref,
        outline: [2, 4],
        search: {
            provider: "local"
        },
        footer: {
            message:
                'Released under the <a href="https://github.com/FabianHardt/k3d-bootstrap-cluster/blob/main/LICENSE">The Prosperity Public License 2.0.0</a>.',
            copyright:
                "This license lets you use and share this software for free, with a trial-length time limit on commercial use."
        },
        nav: [
            {
                text: ref,
                items: [
                    { text: "Changelog", link: "https://github.com/FabianHardt/k3d-bootstrap-cluster/blob/main/CHANGELOG.md" },
                    { text: "Contributing", link: "https://github.com/FabianHardt/k3d-bootstrap-cluster/blob/main/CONTRIBUTING.md" },
                    { text: "Issues", link: "https://github.com/FabianHardt/k3d-bootstrap-cluster/issues" }
                ]
            }
        ],
        editLink: {
            pattern: "https://github.com/FabianHardt/k3d-bootstrap-cluster/blob/main/examples/:path",
            text: "Edit this page on GitHub"
        },
        socialLinks: [
            {
                icon: {
                    svg: '<svg height="32" aria-hidden="true" viewBox="0 0 16 16" version="1.1" width="32" data-view-component="true" class="octicon octicon-mark-github v-align-middle color-fg-default"><path d="M8 0c4.42 0 8 3.58 8 8a8.013 8.013 0 0 1-5.45 7.59c-.4.08-.55-.17-.55-.38 0-.27.01-1.13.01-2.2 0-.75-.25-1.23-.54-1.48 1.78-.2 3.65-.88 3.65-3.95 0-.88-.31-1.59-.82-2.15.08-.2.36-1.02-.08-2.12 0 0-.67-.22-2.2.82-.64-.18-1.32-.27-2-.27-.68 0-1.36.09-2 .27-1.53-1.03-2.2-.82-2.2-.82-.44 1.1-.16 1.92-.08 2.12-.51.56-.82 1.28-.82 2.15 0 3.06 1.86 3.75 3.64 3.95-.23.2-.44.55-.51 1.07-.46.21-1.61.55-2.33-.66-.15-.24-.6-.83-1.23-.82-.67.01-.27.38.01.53.34.19.73.9.82 1.13.16.45.68 1.31 2.69.94 0 .67.01 1.3.01 1.49 0 .21-.15.45-.55.38A7.995 7.995 0 0 1 0 8c0-4.42 3.58-8 8-8Z"></path></svg>'
                },
                link: "https://github.com/FabianHardt/k3d-bootstrap-cluster"
            }
        ],
        sidebar: [
            {
                text: "Introduction",
                collapsible: true,
                items: [
                    { text: "What is k3d-sample-cluster?", link: "/guide/index.html" },
                    { text: "Getting started", link: "/guide/getting-started.html" }
                ]
            },
            {
                text: "Showcases",
                collapsible: true,
                items: [
                    { text: "External DNS", link: "/showcases/external-dns.html" },
                    { text: "Vault", link: "/showcases/vault.html" },
                    { text: "External Secrets Operator", link: "/showcases/external-secrets.html" },
                    { text: "Kong API Gateway", link: "/showcases/kong.html" },
                    { text: "Kuma Service Mesh", link: "/showcases/kuma.html" },
                    { text: "Confluent for Kubernetes", link: "/showcases/confluent.html" },
                    { text: "Kyverno", link: "/showcases/kyverno.html" },
                    { text: "KOng Gateway Operator", link: "/showcases/kong-gateway-operator.html" }
                ]
            },
            {
                text: "Troubleshooting",
                collapsible: true,
                items: [
                    { text: "DNS resolution issues", link: "/troubleshooting/dns-resolution.html" }
                ]
            }
        ]
    }
}