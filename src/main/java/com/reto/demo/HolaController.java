package com.reto.demo;

import java.util.Map;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RestController;

@RestController
public class HolaController {
    @GetMapping("/")
    public Map<String, String> inicio() {
        return Map.of("mensaje", "Hola, mundo desde AWS ECS");
    }

    @GetMapping("/health")
    public Map<String, String> salud() {
        return Map.of("status", "ok");
    }
}
