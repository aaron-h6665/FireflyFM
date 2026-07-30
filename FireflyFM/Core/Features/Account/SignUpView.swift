//
//  SignUpView.swift
//  FireflyFM
//
//  Created by Gemini CLI on 6/8/26.
//

import SwiftUI

struct SignUpView: View {
    @EnvironmentObject private var authManager: AuthManager
    
    let role: SignupRole
    
    @State private var firstName = ""
    @State private var lastName = ""
    @State private var email = ""
    @State private var password = ""
    @State private var confirmPassword = ""
    @State private var isLoading = false
    @State private var errorMessage: String?
    
    // Focus management
    @FocusState private var focusedField: Field?
    
    enum Field: Hashable {
        case firstName, lastName, email, password, confirmPassword
    }
    
    var body: some View {
        ZStack {
            AppConstants.Colors.background.ignoresSafeArea()
            
            // Decorative Glows
            VStack {
                Circle()
                    .fill(AppConstants.Colors.wingMist.opacity(0.4))
                    .frame(width: 400, height: 400)
                    .blur(radius: 60)
                    .offset(x: 150, y: -200)
                Spacer()
                Circle()
                    .fill(AppConstants.Colors.fireflyGlow.opacity(0.16))
                    .frame(width: 300, height: 300)
                    .blur(radius: 50)
                    .offset(x: -150, y: 150)
            }
            
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: 24) {
                        // Logo
                        Image("Logo")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 100, height: 100)
                            .padding(.top, 40)
                        
                        VStack(spacing: 8) {
                            Text("Join Firefly Care")
                                .font(.system(size: 34, weight: .bold, design: .rounded))
                                .foregroundColor(AppConstants.Colors.primaryText)
                            Text("Create a \(role.id.capitalized) account")
                                .font(.subheadline)
                                .foregroundColor(AppConstants.Colors.secondaryText)
                        }
                        
                        VStack(spacing: 16) {
                            AccountTextField(label: "First Name", isFocused: focusedField == .firstName) {
                                TextField("John", text: $firstName)
                                    .focused($focusedField, equals: .firstName)
                                    .textContentType(.givenName)
                                    .submitLabel(.next)
                                    .onSubmit { focusedField = .lastName }
                            }
                            .id(Field.firstName)

                            AccountTextField(label: "Last Name", isFocused: focusedField == .lastName) {
                                TextField("Doe", text: $lastName)
                                    .focused($focusedField, equals: .lastName)
                                    .textContentType(.familyName)
                                    .submitLabel(.next)
                                    .onSubmit { focusedField = .email }
                            }
                            .id(Field.lastName)
                            
                            AccountTextField(label: "Email", isFocused: focusedField == .email) {
                                TextField("name@example.com", text: $email)
                                    .focused($focusedField, equals: .email)
                                    .autocorrectionDisabled()
                                    .textInputAutocapitalization(.never)
                                    .keyboardType(.emailAddress)
                                    .submitLabel(.next)
                                    .onSubmit { focusedField = .password }
                            }
                            .id(Field.email)
                            
                            AccountTextField(label: "Password", isFocused: focusedField == .password) {
                                SecureField("Create a password", text: $password)
                                    .textContentType(.newPassword)
                                    .focused($focusedField, equals: .password)
                                    .submitLabel(.next)
                                    .onSubmit { focusedField = .confirmPassword }
                            }
                            .id(Field.password)
                            
                            AccountTextField(label: "Confirm Password", isFocused: focusedField == .confirmPassword) {
                                SecureField("Repeat your password", text: $confirmPassword)
                                    .textContentType(.newPassword)
                                    .focused($focusedField, equals: .confirmPassword)
                                    .submitLabel(.done)
                                    .onSubmit { focusedField = nil }
                            }
                            .id(Field.confirmPassword)
                        }
                        .padding(.horizontal)
                        
                        // Error Message
                        if let error = errorMessage ?? authManager.errorMessage {
                            Text(error)
                                .font(.caption)
                                .foregroundColor(.red)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal)
                                .padding(.top, 8)
                        }
                        
                        // Sign Up Button
                        Button {
                            focusedField = nil
                            if password != confirmPassword {
                                errorMessage = "The passwords do not match. Re-enter the same password in both password fields."
                                return
                            }
                            errorMessage = nil
                            Task {
                                isLoading = true
                                _ = await authManager.signUp(withEmail: email, password: password, firstName: firstName, lastName: lastName, role: role)
                                isLoading = false
                            }
                        } label: {
                            HStack {
                                if isLoading {
                                    ProgressView().tint(AppConstants.Colors.primaryActionText)
                                } else {
                                    Text("Create Account")
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
                        .padding(.top, 8)
                        .disabled(isLoading || email.isEmpty || password.isEmpty || confirmPassword.isEmpty || firstName.isEmpty || lastName.isEmpty)
                        .opacity(isLoading || email.isEmpty || password.isEmpty || confirmPassword.isEmpty || firstName.isEmpty || lastName.isEmpty ? 0.55 : 1)
                        
                        // Login Link
                        NavigationLink(destination: LoginView()) {
                            HStack(spacing: 4) {
                                Text("Already have an account?")
                                    .foregroundColor(AppConstants.Colors.secondaryText)
                                Text("Sign In")
                                    .fontWeight(.bold)
                                    .foregroundColor(AppConstants.Colors.primaryAction)
                            }
                            .font(.footnote)
                        }
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
        .onAppear {
            authManager.clearError()
            errorMessage = nil
        }
    }
}

private struct AccountTextField<Content: View>: View {
    let label: String
    let isFocused: Bool
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label)
                .font(.caption.bold())
                .foregroundColor(AppConstants.Colors.primaryAction)

            content
                .padding()
                .foregroundColor(AppConstants.Colors.primaryText)
                .tint(AppConstants.Colors.primaryAction)
                .background(AppConstants.Colors.card)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(
                            isFocused ? AppConstants.Colors.primaryAction : AppConstants.Colors.separator,
                            lineWidth: isFocused ? 2 : 1
                        )
                }
        }
    }
}

#Preview("Light") {
    SignUpView(role: .director)
        .environmentObject(AuthManager(service: SupabaseAuthService()))
        .preferredColorScheme(.light)
}

#Preview("Dark") {
    SignUpView(role: .teacher)
        .environmentObject(AuthManager(service: SupabaseAuthService()))
        .preferredColorScheme(.dark)
}
