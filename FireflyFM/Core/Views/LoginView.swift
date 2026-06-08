//
//  LoginView.swift
//  FireflyFM
//
//  Created by Gemini CLI on 6/8/26.
//

import SwiftUI

struct LoginView: View {
    @EnvironmentObject private var authManager: AuthManager
    @State private var email = ""
    @State private var password = ""
    @State private var isLoading = false
    
    var showSignUp: () -> Void
    var signupSuccess: Bool = false
    
    // Firefly Color Palette
    private let backgroundColor = Color(red: 0.10, green: 0.15, blue: 0.20) // Lighter blue-grey
    private let cardColor = Color(red: 0.15, green: 0.22, blue: 0.28)
    private let accentColor = Color.yellow
    
    var body: some View {
        ZStack {
            backgroundColor.ignoresSafeArea()
            
            // Decorative Glows
            VStack {
                Circle()
                    .fill(accentColor.opacity(0.15))
                    .frame(width: 400, height: 400)
                    .blur(radius: 60)
                    .offset(x: -150, y: -200)
                Spacer()
                Circle()
                    .fill(accentColor.opacity(0.1))
                    .frame(width: 300, height: 300)
                    .blur(radius: 50)
                    .offset(x: 150, y: 150)
            }
            
            ScrollView {
                VStack(spacing: 24) {
                    // Logo
                    Image("Logo")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 140, height: 140)
                        .padding(.top, 40)
                    
                    VStack(spacing: 8) {
                        Text("FireflyFM")
                            .font(.system(size: 34, weight: .bold, design: .rounded))
                            .foregroundColor(.white)
                        Text("Light up your music journey")
                            .font(.subheadline)
                            .foregroundColor(.white.opacity(0.7))
                    }
                    
                    if signupSuccess {
                        Text("Account created successfully! Please log in.")
                            .font(.footnote)
                            .fontWeight(.medium)
                            .foregroundColor(.green)
                            .padding()
                            .background(Color.green.opacity(0.1))
                            .cornerRadius(10)
                    }
                    
                    VStack(spacing: 16) {
                        // Email Field
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Email")
                                .font(.caption.bold())
                                .foregroundColor(accentColor)
                            TextField("name@example.com", text: $email)
                                .autocorrectionDisabled()
                                .textInputAutocapitalization(.none) // Fix for uppercase issue
                                .keyboardType(.emailAddress)
                                .padding()
                                .background(cardColor)
                                .cornerRadius(12)
                                .foregroundColor(.white)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12)
                                        .stroke(Color.white.opacity(0.1), lineWidth: 1)
                                )
                        }
                        
                        // Password Field
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Password")
                                .font(.caption.bold())
                                .foregroundColor(accentColor)
                            SecureField("Enter your password", text: $password)
                                .padding()
                                .background(cardColor)
                                .cornerRadius(12)
                                .foregroundColor(.white)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12)
                                        .stroke(Color.white.opacity(0.1), lineWidth: 1)
                                )
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
                                ProgressView().tint(.black)
                            } else {
                                Text("Sign In")
                                    .fontWeight(.bold)
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(accentColor)
                        .foregroundColor(.black)
                        .cornerRadius(12)
                        .shadow(color: accentColor.opacity(0.4), radius: 10, x: 0, y: 5)
                    }
                    .padding(.horizontal)
                    .disabled(isLoading || email.isEmpty || password.isEmpty)
                    
                    // Sign Up Link
                    Button {
                        authManager.clearError()
                        showSignUp()
                    } label: {
                        HStack(spacing: 4) {
                            Text("Don't have an account?")
                                .foregroundColor(.white.opacity(0.7))
                            Text("Create one")
                                .fontWeight(.bold)
                                .foregroundColor(accentColor)
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
        .environmentObject(AuthManager(service: SupabaseAuthService()))
}
