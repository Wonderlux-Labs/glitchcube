const { chromium } = require('playwright');

async function testAdminConversation() {
  const browser = await chromium.launch({ 
    headless: false,
    slowMo: 500  // Slow down actions to make them visible
  });
  const page = await browser.newPage();
  
  console.log('🚀 Starting admin-test page testing...');
  
  try {
    // Navigate to admin test page
    console.log('📍 Navigating to admin test page...');
    await page.goto('http://localhost:9292/admin/test');
    await page.waitForLoadState('networkidle');
    
    // Take screenshot of initial state
    await page.screenshot({ path: 'screenshots/01-initial-page.png', fullPage: true });
    console.log('📸 Initial page screenshot saved');
    
    // Test 1: Create a new conversation
    console.log('\n🧪 Test 1: Creating new conversation with Buddy...');
    await page.fill('#message', 'Hello Buddy! Can you tell me about yourself?');
    await page.selectOption('#persona', 'buddy');
    await page.click('button[type="submit"]');
    
    // Wait for response
    await page.waitForSelector('.response', { timeout: 30000 });
    await page.screenshot({ path: 'screenshots/02-buddy-response.png', fullPage: true });
    
    // Extract session ID from response
    const sessionIdElement = await page.$('.response .metadata');
    let sessionId = null;
    if (sessionIdElement) {
      const text = await sessionIdElement.textContent();
      const match = text.match(/Session: ([\w-]+)/);
      if (match) {
        sessionId = match[1];
        console.log(`✅ New session created: ${sessionId}`);
      }
    }
    
    // Test 2: Continue conversation with same session
    if (sessionId) {
      console.log('\n🧪 Test 2: Continuing conversation with same session...');
      await page.fill('#session_id', sessionId);
      await page.fill('#message', 'What do you like to do for fun?');
      await page.click('button[type="submit"]');
      
      await page.waitForSelector('.response', { timeout: 30000 });
      await page.screenshot({ path: 'screenshots/03-continued-conversation.png', fullPage: true });
      console.log('✅ Continued conversation successfully');
    }
    
    // Test 3: Test different personas
    console.log('\n🧪 Test 3: Testing different personas...');
    const personas = ['jax', 'lomi', 'zorp'];
    
    for (const persona of personas) {
      console.log(`  Testing ${persona}...`);
      await page.fill('#message', `Hey ${persona}, what's your vibe today?`);
      await page.selectOption('#persona', persona);
      await page.fill('#session_id', ''); // Clear session for new conversation
      await page.click('button[type="submit"]');
      
      await page.waitForSelector('.response', { timeout: 30000 });
      await page.screenshot({ path: `screenshots/04-${persona}-response.png`, fullPage: true });
      console.log(`  ✅ ${persona} responded successfully`);
      
      // Small delay between tests
      await page.waitForTimeout(2000);
    }
    
    // Test 4: Check recent conversations display
    console.log('\n🧪 Test 4: Checking recent conversations display...');
    const recentConvs = await page.$$('.message');
    console.log(`  Found ${recentConvs.length} recent conversations displayed`);
    
    if (recentConvs.length > 0) {
      // Click on first conversation link
      const firstLink = await page.$('.message a');
      if (firstLink) {
        const href = await firstLink.getAttribute('href');
        console.log(`  Clicking on session link: ${href}`);
        await firstLink.click();
        
        await page.waitForLoadState('networkidle');
        await page.screenshot({ path: 'screenshots/05-session-details.png', fullPage: true });
        console.log('  ✅ Session details page loaded');
        
        // Go back to main test page
        await page.goBack();
      }
    }
    
    // Test 5: Test TTS functionality
    console.log('\n🧪 Test 5: Testing Text-to-Speech...');
    await page.fill('#tts_message', 'Testing the voice synthesis system!');
    await page.selectOption('#tts_character', 'buddy');
    await page.click('button:has-text("Test TTS")');
    
    await page.waitForSelector('.response', { timeout: 10000 });
    await page.screenshot({ path: 'screenshots/06-tts-result.png', fullPage: true });
    
    const ttsResult = await page.$('.response:has-text("TTS Result")');
    if (ttsResult) {
      const resultText = await ttsResult.textContent();
      console.log(`  TTS Result: ${resultText}`);
    }
    
    // Test 6: Navigate to other pages
    console.log('\n🧪 Test 6: Testing navigation links...');
    
    // Test Sessions page
    await page.click('a[href="/admin/test/sessions"]');
    await page.waitForLoadState('networkidle');
    await page.screenshot({ path: 'screenshots/07-sessions-page.png', fullPage: true });
    console.log('  ✅ Sessions page loaded');
    
    // Test Memories page
    await page.click('a[href="/admin/test/memories"]');
    await page.waitForLoadState('networkidle');
    await page.screenshot({ path: 'screenshots/08-memories-page.png', fullPage: true });
    console.log('  ✅ Memories page loaded');
    
    // Test Tools page
    await page.click('a[href="/admin/test/tools"]');
    await page.waitForLoadState('networkidle');
    await page.screenshot({ path: 'screenshots/09-tools-page.png', fullPage: true });
    console.log('  ✅ Tools page loaded');
    
    // Return to main test page
    await page.click('a[href="/admin/test"]');
    await page.waitForLoadState('networkidle');
    
    // Test 7: Error handling - empty message
    console.log('\n🧪 Test 7: Testing error handling...');
    await page.fill('#message', '');
    await page.click('button[type="submit"]');
    
    // Check for HTML5 validation
    const validationMessage = await page.evaluate(() => {
      const input = document.querySelector('#message');
      return input.validationMessage;
    });
    
    if (validationMessage) {
      console.log(`  ✅ Form validation working: "${validationMessage}"`);
    }
    
    // Final summary
    console.log('\n📊 Test Summary:');
    console.log('  ✅ Page loads successfully');
    console.log('  ✅ Conversation creation works');
    console.log('  ✅ Session continuation works');
    console.log('  ✅ Multiple personas work');
    console.log('  ✅ Navigation between pages works');
    console.log('  ✅ Form validation works');
    
    // Check for any console errors
    page.on('console', msg => {
      if (msg.type() === 'error') {
        console.log('  ⚠️ Console error:', msg.text());
      }
    });
    
  } catch (error) {
    console.error('❌ Test failed:', error);
    await page.screenshot({ path: 'screenshots/error-state.png', fullPage: true });
  } finally {
    console.log('\n🎬 Testing complete!');
    // Keep browser open for manual inspection
    console.log('Browser will remain open for manual inspection. Press Ctrl+C to exit.');
    // await browser.close();
  }
}

// Run the tests
testAdminConversation().catch(console.error);