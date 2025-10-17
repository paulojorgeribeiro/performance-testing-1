import com.sun.net.httpserver.HttpServer;
import com.sun.net.httpserver.HttpHandler;
import com.sun.net.httpserver.HttpExchange;

import java.io.IOException;
import java.io.OutputStream;
import java.net.InetSocketAddress;
import java.util.Scanner;
import java.util.concurrent.Executors;
import java.util.concurrent.atomic.AtomicInteger;
import java.util.concurrent.atomic.AtomicBoolean;
import java.util.Random;

public class HttpServerApp {

    static AtomicInteger delay = new AtomicInteger(2000); // Default 2000ms
    static AtomicBoolean returnError = new AtomicBoolean(false);

    public static void main(String[] args) throws IOException {
        HttpServer server = HttpServer.create(new InetSocketAddress(8082), 0);

        // Rename the existing service to "/service1"
        server.createContext("/service1", new MyHandler());

        // Add a new service at "/service2"
        server.createContext("/service2", new Service2Handler());

        server.setExecutor(Executors.newCachedThreadPool());
        server.start();
        System.out.println("Server started on port 8082");

        // Start the control menu in a background thread
        new Thread(HttpServerApp::runControlMenu).start();
    }

    public static void runControlMenu() {
        Scanner scanner = new Scanner(System.in);
        while (true) {
            System.out.println("\n--- Control Menu ---");
            System.out.println("Current delay: " + delay.get() + " ms");
            System.out.println("Error mode: " + (returnError.get() ? "ON" : "OFF"));
            System.out.println("------------------------");
            System.out.println("1. Increase response time (+500ms)");
            System.out.println("2. Decrease response time (-500ms)");
            System.out.println("3. Toggle error mode");
            System.out.println("4. Exit");
            System.out.print("Choose an option: ");
            String input = scanner.nextLine();
            switch (input) {
                case "1":
                    delay.addAndGet(500);
                    break;
                case "2":
                    delay.updateAndGet(val -> Math.max(0, val - 500));
                    break;
                case "3":
                    returnError.set(!returnError.get());
                    break;
                case "4":
                    System.out.println("Exiting...");
                    System.exit(0);
                    break;
                default:
                    System.out.println("Invalid option. Try again.");
            }
        }
    }

    // Existing handler, now mapped to "/service1"
    static class MyHandler implements HttpHandler {
        private final Random random = new Random();

        @Override
        public void handle(HttpExchange exchange) throws IOException {
            if (returnError.get()) {
                int[] errorCodes = {400, 401, 403, 404, 500};
                int code = errorCodes[random.nextInt(errorCodes.length)];
                String errorResponse = "Simulated error: " + code;
                exchange.sendResponseHeaders(code, errorResponse.length());
                OutputStream os = exchange.getResponseBody();
                os.write(errorResponse.getBytes());
                os.close();
                return;
            }

            long endTime = System.currentTimeMillis() + delay.get();
            while (System.currentTimeMillis() < endTime) {
                double temp = Math.sqrt(System.currentTimeMillis());
            }

            String response = "Response after " + delay.get() + "ms";
            exchange.sendResponseHeaders(200, response.length());
            OutputStream os = exchange.getResponseBody();
            os.write(response.getBytes());
            os.close();
        }
    }

    // New handler for "/service2"
    static class Service2Handler implements HttpHandler {
        @Override
        public void handle(HttpExchange exchange) throws IOException {
            String response = "Hello from Service 2!";
            exchange.sendResponseHeaders(200, response.length());
            OutputStream os = exchange.getResponseBody();
            os.write(response.getBytes());
            os.close();
        }
    }
}
