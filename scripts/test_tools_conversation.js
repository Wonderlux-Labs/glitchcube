const { chromium } = require('playwright');

async function testToolsConversation() {
  const browser = await chromium.launch({ 
    headless: false,
    slowMo: 500
  });
  const page = await browser.newPage();
  
  console.log('🚀 Testing conversation with tools...\n');
  
  try {
    // Navigate to improved admin test page
    console.log('📍 Navigating to admin test page...');
    await page.goto('http://localhost:9292/admin/test');
    await page.waitForLoadState('networkidle');
    
    // Test conversations that might trigger tools
    const testMessages = [
      { persona: 'buddy', message: "Hey Buddy! Can you turn on some party lights?" },
      { persona: 'jax', message: "Jax, play some classic rock music!" },
      { persona: 'lomi', message: "Lomi darling, can you make the display show something fabulous?" },
      { persona: 'zorp', message: "Yo Zorp! Crank up the party vibes with lights and music!" }
    ];
    
    for (const test of testMessages) {
      console.log(`\n🧪 Testing ${test.persona} with: "${test.message}"`);
      console.log('─'.repeat(60));
      
      // Select persona by clicking the persona button
      await page.click(`.persona-option[data-persona="${test.persona}"]`);
      
      // Enter message
      await page.fill('#message', test.message);
      
      // Clear session for new conversation
      await page.fill('#session_id', '');
      
      // Send message
      await page.click('button[type="submit"]');
      
      // Wait for response
      await page.waitForSelector('.response', { timeout: 10000 });
      
      // Extract response details
      const response = await page.$eval('.response', el => el.textContent);
      console.log(`✅ Response received`);
      
      // Check for metadata
      const metadata = await page.$eval('.metadata', el => el.textContent).catch(() => 'No metadata');
      console.log(`📊 Metadata: ${metadata}`);
      
      // Check if response mentions any tool-related actions
      if (response.includes('light') || response.includes('music') || response.includes('display')) {
        console.log(`🔧 Response mentions tool-related actions`);
      }
      
      // Take screenshot
      await page.screenshot({ 
        path: `screenshots/tools-${test.persona}-${Date.now()}.png`, 
        fullPage: true 
      });
      
      await page.waitForTimeout(2000);
    }
    
    console.log('\n═══════════════════════════════════════');
    console.log('📊 Tool Testing Summary:');
    console.log('═══════════════════════════════════════');
    console.log('✅ All personas tested with tool-triggering messages');
    console.log('✅ Responses received for all requests');
    console.log('📝 Check server logs for actual tool execution details');
    
    console.log('\nBrowser will remain open for inspection...');
    
  } catch (error) {
    console.error('\n❌ Test failed:', error);
    await page.screenshot({ path: 'screenshots/tools-error.png', fullPage: true });
  }
}

// Run the test
testToolsConversation().catch(console.error);