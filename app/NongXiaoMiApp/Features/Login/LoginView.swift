import SwiftUI

// MARK: - 登录页(对应 LoginActivity.java: 手机号+密码, 注册带邀请码)

struct LoginView: View {
    @EnvironmentObject var appState: AppState
    @State private var phone = ""
    @State private var password = ""
    @State private var invite = ""
    @State private var isRegister = false
    @State private var busy = false
    @State private var err = ""

    var body: some View {
        VStack(spacing: 16) {
            Spacer()
            Text("农小秘")
                .font(.largeTitle).bold()
            Text("农事记录 · 地块管理 · 收支账本")
                .font(.subheadline).foregroundColor(.secondary)
            Spacer()

            VStack(spacing: 12) {
                TextField("手机号", text: $phone)
                    .keyboardType(.numberPad)
                    .textFieldStyle(.roundedBorder)
                SecureField("密码", text: $password)
                    .textFieldStyle(.roundedBorder)
                if isRegister {
                    TextField("邀请码(老用户给你)", text: $invite)
                        .textFieldStyle(.roundedBorder)
                }
                if !err.isEmpty {
                    Text(err).font(.footnote).foregroundColor(.red)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                Button {
                    Task {
                        busy = true; err = ""
                        await login()
                        busy = false
                    }
                } label: {
                    Group {
                        if busy { ProgressView() }
                        else { Text(isRegister ? "注册并登录" : "登录").bold() }
                    }
                    .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.borderedProminent)
                .disabled(busy || phone.isEmpty || password.isEmpty)

                Button(isRegister ? "已有账号, 去登录" : "新用户注册") {
                    isRegister.toggle(); err = ""
                }
                .font(.footnote)
            }
            .padding()
            Spacer()
        }
        .padding(.horizontal, 32)
    }

    private func login() async {
        if isRegister {
            // 注册: 服务端 /api/register(手机号+密码+邀请码), 成功后自动登录
            do {
                let r = try await appState.api.post("/api/register", body: [
                    "phone": phone, "password": password, "invite": invite,
                ])
                if let e = r["err"] as? String {
                    err = e; return
                }
            } catch {
                err = "注册失败: \(error.localizedDescription)"; return
            }
        }
        await appState.doLogin(phone: phone, password: password, invite: invite)
        if !appState.isLoggedIn {
            err = appState.syncMessage.isEmpty ? "登录失败" : appState.syncMessage
        }
    }
}
