//
//  LoginView.swift
//  FireflyFM
//
//  Created by Gemini CLI on 6/8/26.
//

import SwiftUI
import JGProgressHUD

struct LoginView: View {
    
//    private let spinner = JGProgressHUD(.dark)
    
    @EnvironmentObject private var authManager: AuthManager
    @Environment(\.dismiss) private var dismiss
    
    @State private var email = ""
    @State private var password = ""
    @State private var isLoading = false
    
    @FocusState private var focusedField: Field?
    
    enum Field: Hashable {
        case email, password
    }
    
    // var showSignUp: () -> Void
    // var signupSuccess: Bool = false
    
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
                                .foregroundColor(.white)
                            Text("Sign in to continue")
                                .font(.subheadline)
                                .foregroundColor(.white.opacity(0.7))
                        }
                        
//                        if signupSuccess {
//                            Text("Account created successfully! Please log in.")
//                                .font(.footnote)
//                                .fontWeight(.medium)
//                                .foregroundColor(.green)
//                                .padding()
//                                .background(Color.green.opacity(0.1))
//                                .cornerRadius(10)
//                        }
//                        
                        VStack(spacing: 16) {
                            // Email Field
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Email")
                                    .font(.caption.bold())
                                    .foregroundColor(AppConstants.Colors.card)
                                TextField("name@example.com", text: $email)
                                    .focused($focusedField, equals: .email)
                                    .autocorrectionDisabled()
                                    .textInputAutocapitalization(.never) // Use .never for maximum compatibility
                                    .keyboardType(.emailAddress)
                                    .submitLabel(.next)
                                    .onSubmit { focusedField = .password }
                                    .padding()
                                    .background(AppConstants.Colors.card)
                                    .cornerRadius(12)
                                    .foregroundColor(.white)
                                    .tint(AppConstants.Colors.card)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 12)
                                            .stroke(focusedField == .email ? AppConstants.Colors.card.opacity(0.5) : Color.white.opacity(0.1), lineWidth: 1)
                                    )
                            }
                            .id(Field.email)
                            
                            // Password Field
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Password")
                                    .font(.caption.bold())
                                    .foregroundColor(AppConstants.Colors.card)
                                SecureField("Enter your password", text: $password)
                                    .focused($focusedField, equals: .password)
                                    .submitLabel(.done)
                                    .onSubmit { focusedField = nil }
                                    .padding()
                                    .background(AppConstants.Colors.card)
                                    .cornerRadius(12)
                                    .foregroundColor(.white)
                                    .tint(AppConstants.Colors.card)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 12)
                                            .stroke(focusedField == .password ? AppConstants.Colors.card.opacity(0.5) : Color.white.opacity(0.1), lineWidth: 1)
                                    )
                            }
                            .id(Field.password)
                        }
                        .padding(.horizontal)
                        
                        if let error = authManager.error {
                            Text(error.localizedDescription)
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
                                    ProgressView().tint(.black)
                                } else {
                                    Text("Sign In")
                                        .fontWeight(.bold)
                                }
                            }
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(AppConstants.Colors.card)
                            .foregroundColor(.black)
                            .cornerRadius(12)
                            .shadow(color: AppConstants.Colors.card.opacity(0.4), radius: 10, x: 0, y: 5)
                        }
                        .padding(.horizontal)
                        .disabled(isLoading || email.isEmpty || password.isEmpty)
                        
                        // 2. The Cross-Link to Role Selection
                        NavigationLink(destination: RoleSelectionView()) {
                            HStack(spacing: 4) {
                                Text("Don't have an account?")
                                    .foregroundColor(.white.opacity(0.85))
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
//                        Button {
//                            authManager.clearError()
//                            showSignUp()
//                        } label: {
//                            HStack(spacing: 4) {
//                                Text("Don't have an account?")
//                                    .foregroundColor(.white.opacity(0.7))
//                                Text("Create one")
//                                    .fontWeight(.bold)
//                                    .foregroundColor(accentColor)
//                            }
//                            .font(.footnote)
//                        }
//                        .padding(.bottom, 20)
//                    }
//                    .padding()
//                }
//                .onChange(of: focusedField) { _, newValue in
//                    if let newValue {
//                        withAnimation {
//                            proxy.scrollTo(newValue, anchor: .center)
                        }
                    }
                }
            }
        }
    }
}

#Preview {
    LoginView()
        .environmentObject(AuthManager(service: SupabaseAuthService()))
}
