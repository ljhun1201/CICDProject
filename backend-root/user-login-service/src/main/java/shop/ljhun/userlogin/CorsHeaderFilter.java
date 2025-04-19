package shop.ljhun.userlogin;

import jakarta.servlet.*;
import jakarta.servlet.http.HttpServletResponse;
import org.springframework.stereotype.Component;

import java.io.IOException;

@Component
public class CorsHeaderFilter implements Filter {

    @Override
    public void doFilter(ServletRequest request, ServletResponse response, FilterChain chain)
            throws IOException, ServletException {

        HttpServletResponse res = (HttpServletResponse) response;
        String origin = ((jakarta.servlet.http.HttpServletRequest) request).getHeader("Origin");

        // 허용할 도메인 목록
        if ("https://www.ljhun.shop".equals(origin) || "https://ljhun.shop".equals(origin)) {
            res.setHeader("Access-Control-Allow-Origin", origin); // 요청 Origin을 그대로 echo
            res.setHeader("Access-Control-Allow-Credentials", "true");
            res.setHeader("Access-Control-Allow-Methods", "GET, POST, OPTIONS");
            res.setHeader("Access-Control-Allow-Headers", "content-type, authorization");
            res.setHeader("Vary", "Origin");
        }

        chain.doFilter(request, response);
    }
}