//
//  LoginView.swift
//  FireflyFM
//
//  Created by Gemini CLI on 6/8/26.
//

import SwiftUI

struct LoginView: View {
    @Environment(AuthManager.self) private var authManager
    @State private var email = ""
    @State private var password = ""
    @State private var isLoading = false
    
    var showSignUp: () -> Void
    
    var body: some View {
        ZStack {
            // Background
            Color(red: 0.04, green: 0.07, blue: 0.09).ignoresSafeArea()
            
            // Background Glow Decor
            VStack {
                Circle()
                    .fill(Color.yellow.opacity(0.1))
                    .frame(width: 300, height: 300)
                    .blur(radius: 50)
                    .offset(x: -100, y: -150)
                Spacer()
                Circle()
                    .fill(Color.yellow.opacity(0.05))
                    .frame(width: 250, height: 250)
                    .blur(radius: 40)
                    .offset(x: 100, y: 100)
            }
            
            ScrollView {
                VStack(spacing: 32) {
                    // Logo
                    Image("Logo")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 120, height: 120)
                        .padding(.top, 60)
                    
                    VStack(alignment: .leading, spacing: 8) {
                        Text("FireflyFM")
                            .font(.largeTitle)
                            .fontWeight(.bold)
                            .foregroundColor(.white)
                        Text("Welcome back, sign in to continue")
                            .font(.subheadline)
                            .foregroundColor(.gray)
                    }
                    
                    VStack(spacing: 20) {
                        // Email Field
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Email")
                                .font(.caption)
                                .foregroundColor(.gray)
                            TextField("Enter your email", text: $email)
                                .padding()
                                .background(Color.white.opacity(0.05))
                                .cornerRadius(12)
                                .foregroundColor(.white)
                                .textInputAutocapitalization(.none)
                                .keyboardType(.emailAddress)
                        }
                        
                        // Password Field
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Password")
                                .font(.caption)
                                .foregroundColor(.gray)
                            SecureField("Enter your password", text: $password)
                                .padding()
                                .background(Color.white.opacity(0.05))
                                .cornerRadius(12)
                                .foregroundColor(.white)
                        }
                    }
                    .padding(.horizontal)
                    
                    // Error Message
                    if let error = authManager.error {
                        Text(error.localizedDescription)
                            .font(.caption)
                            .foregroundColor(.red)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                    }
                    
                    // Login Button
                    Button {
                        Task {
                            isLoading = true
                            await authManager.login(withEmail: email, password: password)
                            isLoading = false
                        }
                    } label: {
                        HStack {
                            if isLoading {
                                ProgressView()
                                    .tint(.black)
                            } else {
                                Text("Login")
                                    .fontWeight(.semibold)
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.yellow)
                        .foregroundColor(.black)
                        .cornerRadius(12)
                        .shadow(color: .yellow.opacity(0.3), radius: 10, x: 0, y: 5)
                    }
                    .padding(.horizontal)
                    .disabled(isLoading || email.isEmpty || password.isEmpty)
                    
                    // Sign Up Link
                    Button {
                        showSignUp()
                    } label: {
                        HStack(spacing: 4) {
                            Text("Don't have an account?")
                                .foregroundColor(.gray)
                            Text("Sign up")
                                .fontWeight(.bold)
                                .foregroundColor(.yellow)
                        }
                        .font(.footnote)
                    }
                    .padding(.bottom, 20)
                }
                .padding()
            }
        }
    }
}

#Preview {
    LoginView(showSignUp: {})
        .environment(AuthManager(service: SupabaseAuthService()))
}
