//
//  LoginView.swift
//  FireflyFM
//
//  Created by Gemini CLI on 6/8/26.
//

import SwiftUI

struct LoginView: View {
    @EnvironmentObject private var authManager: AuthManager
    @Environment(\.dismiss) private var dismiss
    
    @State private var email = ""
    @State private var password = ""
    @State private var isLoading = false
    
    @FocusState private var focusedField: Field?
    
    enum Field: Hashable {
        case email, password
    }
    
    var body: some View {
        ZStack {
            AppConstants.Colors.background.ignoresSafeArea()
            
            VStack {
                Circle()
                    .fill(AppConstants.Colors.accessibleYellow.opacity(0.15))
                    .frame(width: 400, height: 400)
                    .blur(radius: 60)
                    .offset(x: -150, y: -200)
                Spacer()
                Circle()
                    .fill(AppConstants.Colors.accessibleYellow.opacity(0.1))
                    .frame(width: 300, height: 300)
                    .blur(radius: 50)
                    .offset(x: 150, y: 150)
            }
            
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: 24) {
                        Image("Logo")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 140, height: 140)
                            .padding(.top, 40)
                        
                        VStack(spacing: 8) {
                            Text("Welcome Back")
                                .font(.system(size: 34, weight: .bold, design: .rounded))
                                .foregroundColor(AppConstants.Colors.primaryText)
                            Text("Sign in to continue")
                                .font(.subheadline)
                                .foregroundColor(AppConstants.Colors.primaryText.opacity(0.7))
                        }
                        
                        VStack(spacing: 16) {
                            // Email Field
                            AccountTextField(label: "Email", isFocused: focusedField == .email) {
                                TextField("name@example.com", text: $email)
                                    .focused($focusedField, equals: .email)
                                    .autocorrectionDisabled()
                                    .textInputAutocapitalization(.never)
                                    .keyboardType(.emailAddress)
                                    .textContentType(.emailAddress)
                                    .submitLabel(.next)
                                    .onSubmit { focusedField = .password }
                            }
                            .id(Field.email)
                            
                            // Password Field
                            AccountTextField(label: "Password", isFocused: focusedField == .password) {
                                SecureField("Enter your password", text: $password)
                                    .focused($focusedField, equals: .password)
                                    .textContentType(.password)
                                    .submitLabel(.done)
                                    .onSubmit { focusedField = nil }
                            }
                            .id(Field.password)
                        }
                        .padding(.horizontal)
                        
                        if let errorMessage = authManager.errorMessage {
                            Text(errorMessage)
                                .font(.caption)
                                .foregroundColor(.red)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal)
                        }
                        
                        Button {
                            focusedField = nil
                            Task {
                                isLoading = true
                                await authManager.login(withEmail: email, password: password)
                                isLoading = false
                            }
                        } label: {
                            HStack {
                                if isLoading {
                                    ProgressView().tint(AppConstants.Colors.primaryActionText)
                                } else {
                                    Text("Sign In")
                                        .fontWeight(.bold)
                                }
                            }
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(AppConstants.Colors.primaryAction)
                            .foregroundColor(AppConstants.Colors.primaryActionText)
                            .cornerRadius(12)
                            .shadow(color: AppConstants.Colors.primaryAction.opacity(0.22), radius: 10, x: 0, y: 5)
                        }
                        .padding(.horizontal)
                        .disabled(isLoading || email.isEmpty || password.isEmpty)
                        
                        // 2. The Cross-Link to Role Selection
                        NavigationLink(destination: RoleSelectionView()) {
                            HStack(spacing: 4) {
                                Text("Don't have an account?")
                                    .foregroundColor(AppConstants.Colors.primaryText.opacity(0.85))
                                Text("Create one")
                                    .fontWeight(.bold)
                                    .foregroundColor(AppConstants.Colors.accessibleYellow)
                            }
                            .font(.footnote)
                        }
                        .padding(.top, 10)
                        .padding(.bottom, 20)
                    }
                    .padding()
                }
                .onChange(of: focusedField) { _, newValue in
                    if let newValue {
                        withAnimation {
                            proxy.scrollTo(newValue, anchor: .center)
                        }
                    }
                }
            }
        }
    }
}

#Preview("Light") {
    LoginView()
        .environmentObject(AuthManager(service: SupabaseAuthService()))
        .preferredColorScheme(.light)
}

#Preview("Dark") {
    LoginView()
        .environmentObject(AuthManager(service: SupabaseAuthService()))
        .preferredColorScheme(.dark)
}
