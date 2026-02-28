package com.deneme.account_service.config.Controller;
import org.springframework.http.ResponseEntity;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.security.oauth2.jwt.Jwt;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

import java.math.BigDecimal;
import java.util.HashMap;
import java.util.Map;

@RestController
@RequestMapping("/api/v1/accounts")
public class AccountController {

    @GetMapping("/balance")
    public ResponseEntity<Map<String, Object>> getBalance(@AuthenticationPrincipal Jwt jwt) {
        String userId = jwt.getSubject();
        String username = jwt.getClaimAsString("preferred_username");
        String email = jwt.getClaimAsString("email");
        System.out.println("Bakiye sorgusu yapan User ID: " + userId);
        Map<String, Object> response = new HashMap<>();
        response.put("userId", userId);
        response.put("owner", username);
        response.put("email", email);
        response.put("balance", new BigDecimal("15450.75"));
        response.put("currency", "TRY");
        response.put("message", "Bakiye basariyla getirildi.");

        return ResponseEntity.ok(response);
    }
}
