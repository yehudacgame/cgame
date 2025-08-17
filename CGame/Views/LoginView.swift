import SwiftUI

struct LoginView: View {
    @EnvironmentObject var authViewModel: AuthViewModel
    @State private var email = ""
    @State private var password = ""
    @State private var isSignUp = false
    
    var body: some View {
        VStack(spacing: 32) {
            Spacer()
            
            VStack(spacing: 16) {
                Image(systemName: "gamecontroller.fill")
                    .font(.system(size: 80))
                    .foregroundColor(.blue)
                
                Text("CGame")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                
                Text("Capture your best gaming moments")
                    .font(.headline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
            
            VStack(spacing: 16) {
                TextField("Email", text: $email)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .textContentType(.emailAddress)
                    .autocapitalization(.none)
                
                SecureField("Password", text: $password)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .textContentType(isSignUp ? .newPassword : .password)
                
                Button(action: {
                    if isSignUp {
                        authViewModel.signUp(email: email, password: password)
                    } else {
                        authViewModel.signIn(email: email, password: password)
                    }
                }) {
                    HStack {
                        if authViewModel.isLoading {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                .scaleEffect(0.8)
                        }
                        
                        Text(isSignUp ? "Sign Up" : "Sign In")
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(10)
                }
                .disabled(email.isEmpty || password.isEmpty || authViewModel.isLoading)
                
                Button("Don't have an account? Sign Up") {
                    isSignUp.toggle()
                }
                .foregroundColor(.blue)
                
                Divider()
                
                Button("Continue with Local Testing") {
                    authViewModel.signInWithApple(result: "local-testing")
                }
                .buttonStyle(CGameSecondaryButtonStyle())
            }
            .padding(.horizontal, 32)
            
            Spacer()
            
            if let error = authViewModel.errorMessage {
                Text(error)
                    .foregroundColor(.red)
                    .padding()
                    .background(Color.red.opacity(0.1))
                    .cornerRadius(8)
                    .padding(.horizontal, 32)
            }
        }
        .onAppear {
            isSignUp = false
        }
    }
}