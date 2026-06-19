//
//  SignUpView.swift
//  FireflyFM
//
//  Created by Gemini CLI on 6/8/26.
//

import SwiftUI

struct SignUpView: View {
    @EnvironmentObject private var authManager: AuthManager
    
    let role: UserRole
    
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
    
    // Firefly Color Palette
    private let backgroundColor = Color(red: 0.10, green: 0.15, blue: 0.20)
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
                    .offset(x: 150, y: -200)
                Spacer()
                Circle()
                    .fill(accentColor.opacity(0.1))
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
                                .foregroundColor(.white)
                            Text("Create a \(role.id.capitalized) account")
                                .font(.subheadline)
                                .foregroundColor(.white.opacity(0.7))
                        }
                        
                        VStack(spacing: 16) {
                            // First Name Field
                            VStack(alignment: .leading, spacing: 8) {
                                Text("First Name")
                                    .font(.caption.bold())
                                    .foregroundColor(accentColor)
                                TextField("John", text: $firstName)
                                    .focused($focusedField, equals: .firstName)
                                    .textContentType(.givenName)
                                    .submitLabel(.next)
                                    .onSubmit { focusedField = .lastName }
                                    .padding()
                                    .background(cardColor)
                                    .cornerRadius(12)
                                    .foregroundColor(.white)
                                    .tint(accentColor)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 12)
                                            .stroke(focusedField == .firstName ? accentColor.opacity(0.5) : Color.white.opacity(0.1), lineWidth: 1)
                                    )
                            }
                            .id(Field.firstName)

                            // Last Name Field
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Last Name")
                                    .font(.caption.bold())
                                    .foregroundColor(accentColor)
                                TextField("Doe", text: $lastName)
                                    .focused($focusedField, equals: .lastName)
                                    .textContentType(.familyName)
                                    .submitLabel(.next)
                                    .onSubmit { focusedField = .email }
                                    .padding()
                                    .background(cardColor)
                                    .cornerRadius(12)
                                    .foregroundColor(.white)
                                    .tint(accentColor)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 12)
                                            .stroke(focusedField == .lastName ? accentColor.opacity(0.5) : Color.white.opacity(0.1), lineWidth: 1)
                                    )
                            }
                            .id(Field.lastName)
                            
                            // Email Field
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Email")
                                    .font(.caption.bold())
                                    .foregroundColor(accentColor)
                                TextField("name@example.com", text: $email)
                                    .focused($focusedField, equals: .email)
                                    .autocorrectionDisabled()
                                    .textInputAutocapitalization(.never) // Use .never to explicitly kill capitalization
                                    .keyboardType(.emailAddress)
                                    .submitLabel(.next)
                                    .onSubmit { focusedField = .password }
                                    .padding()
                                    .background(cardColor)
                                    .cornerRadius(12)
                                    .foregroundColor(.white)
                                    .tint(accentColor)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 12)
                                            .stroke(focusedField == .email ? accentColor.opacity(0.5) : Color.white.opacity(0.1), lineWidth: 1)
                                    )
                            }
                            .id(Field.email)
                            
                            // Password Field
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Password")
                                    .font(.caption.bold())
                                    .foregroundColor(accentColor)
                                SecureField("Create a password", text: $password)
                                    .textContentType(.newPassword) 
                                    .focused($focusedField, equals: .password)
                                    .submitLabel(.next)
                                    .onSubmit { focusedField = .confirmPassword }
                                    .padding()
                                    .background(cardColor)
                                    .cornerRadius(12)
                                    .foregroundColor(.white)
                                    .tint(accentColor)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 12)
                                            .stroke(focusedField == .password ? accentColor.opacity(0.5) : Color.white.opacity(0.1), lineWidth: 1)
                                    )
                            }
                            .id(Field.password)
                            
                            // Confirm Password Field
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Confirm Password")
                                    .font(.caption.bold())
                                    .foregroundColor(accentColor)
                                SecureField("Repeat your password", text: $confirmPassword)
                                    .textContentType(.newPassword)
                                    .focused($focusedField, equals: .confirmPassword)
                                    .submitLabel(.done)
                                    .onSubmit { focusedField = nil }
                                    .padding()
                                    .background(cardColor)
                                    .cornerRadius(12)
                                    .foregroundColor(.white)
                                    .tint(accentColor)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 12)
                                            .stroke(focusedField == .confirmPassword ? accentColor.opacity(0.5) : Color.white.opacity(0.1), lineWidth: 1)
                                    )
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
                                    ProgressView().tint(.black)
                                } else {
                                    Text("Create Account")
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
                        .padding(.top, 8)
                        .disabled(isLoading || email.isEmpty || password.isEmpty || confirmPassword.isEmpty || firstName.isEmpty || lastName.isEmpty)
                        
                        // Login Link
                        NavigationLink(destination: LoginView()) {
                            HStack(spacing: 4) {
                                Text("Already have an account?")
                                    .foregroundColor(.white.opacity(0.7))
                                Text("Sign In")
                                    .fontWeight(.bold)
                                    .foregroundColor(accentColor)
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

#Preview {
    SignUpView(role: .director)
        .environmentObject(AuthManager(service: SupabaseAuthService()))
}
